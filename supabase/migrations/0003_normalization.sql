-- Consentra · Migration 0003: normalization layer
--
-- Why this exists. Cross-provider reconciliation only scales nationally if it
-- matches on *codes*, not strings. "Lisinopril" at a US Epic site and
-- "Lisinopril 10mg tablets" at an NHS trust are the same RxNorm ingredient;
-- "HbA1c 48 mmol/mol" (UK, IFCC) and "HbA1c 6.5 %" (US, NGSP) are the same
-- LOINC 4548-4 in different units. This migration adds:
--
--   1. jurisdictions      — the health-data regimes a provider belongs to, seeded
--                            from Consentra's national-readiness research (Nov 2026).
--   2. drug_concepts      — canonical ingredient (RxNorm RXCUI) with UK dm+d /
--                            SNOMED and ATC crosswalk; providers map by code.
--   3. unit_conversions   — LOINC + UCUM source → canonical unit, with factor or
--                            formula (HbA1c IFCC↔NGSP is affine, not linear).
--   4. normalized views   — medications_canonical, observations_canonical: every
--                            provider's row expressed in one vocabulary + one unit.
--   5. detect_discrepancies() upgraded: dose conflicts match on canonical drug,
--                            dose compared in canonical units; new unit_mismatch
--                            rule for labs with incompatible units across sources.
--
-- Additive and idempotent. Nothing in 0001/0002 is dropped.

-- ---------------------------------------------------------------------------
-- 1. Jurisdictions (national data regimes)
-- ---------------------------------------------------------------------------
create table if not exists jurisdictions (
  code              char(2) primary key,            -- ISO 3166-1 alpha-2
  name              text not null,
  regime            text not null,                  -- the data-exchange framework in force
  patient_identity  text,                           -- national eID / identifier scheme
  fhir_profile      text,                           -- which IG providers there speak
  lab_unit_system   text not null default 'UCUM',   -- UCUM everywhere; convention differs
  hba1c_convention  text not null default 'NGSP',   -- NGSP (%) or IFCC (mmol/mol)
  glucose_unit      text not null default 'mg/dL',
  access_status     text not null,                  -- can a third party reach records today
  access_note       text,
  evidence_url      text,
  researched_on     date
);

insert into jurisdictions (code, name, regime, patient_identity, fhir_profile, hba1c_convention, glucose_unit, access_status, access_note, evidence_url, researched_on) values
  ('US', 'United States', 'TEFCA / Individual Access Services (IAS); CMS Patient Access API; 21st Century Cures information-blocking rule',
   'No national ID; IAS requires IAL2 identity verification per QHIN agreement', 'US Core (HL7 FHIR R4)', 'NGSP', 'mg/dL',
   'open', 'Third-party IAS access live via QHINs; IAS exchange disrupted Oct 2026 during SOP v3.0 rollout; QHIN non-compliance deadline 26 Oct 2026.',
   'https://rce.sequoiaproject.org/', '2026-10-30'),
  ('GB', 'United Kingdom', 'NHS England Single Patient Record; GP Connect; UK GDPR + Data (Use and Access) Act 2025',
   'NHS login (citizen, OIDC); NHS CIS2 smartcard (clinician)', 'UK Core (HL7 FHIR R4)', 'IFCC', 'mmol/L',
   'gated', 'Patient-facing integration requires NHS login; NHS England building consent/audit inside the NHS App itself.',
   'https://digital.nhs.uk/services/nhs-login', '2026-10-30'),
  ('DE', 'Germany', 'ePA (elektronische Patientenakte) via gematik; EHDS from 26 Mar 2027',
   'Gesundheits-ID / eGK, gematik IDP (LoA high)', 'ISiK / KBV profiles (FHIR R4)', 'NGSP', 'mg/dL',
   'gated', 'Distribution is the blocker: patients meet the ecosystem inside their insurer''s app.',
   'https://www.gematik.de/anwendungen/epa', '2026-10-30'),
  ('ES', 'Spain', '17 regional health services; EHDS from 26 Mar 2027',
   'DNI electrónico, Cl@ve', 'IPS / EHDS European EHR exchange format', 'NGSP', 'mg/dL',
   'federated', 'A national agreement does not deliver data; each autonomous community holds its own records.',
   'https://health.ec.europa.eu/ehealth-digital-health-and-care/european-health-data-space_en', '2026-10-30'),
  ('DK', 'Denmark', 'sundhed.dk national portal; EHDS from 26 Mar 2027',
   'MitID; CPR number', 'DK Core (FHIR R4)', 'IFCC', 'mmol/L',
   'closed', 'Mature but closed: excellent data, Danish-only, no third-party path.',
   'https://www.sundhed.dk/', '2026-10-30'),
  ('TW', 'Taiwan', 'NHI MediCloud + My Health Bank (健康存摺) export; TW Core IG',
   'NHI card; Taiwan FidO', 'TW Core IG (FHIR R4)', 'NGSP', 'mg/dL',
   'patient-export', 'Patient can export an encrypted bundle from the NHI app; 11 record categories; mixed UTF-8/Big5 encodings.',
   'https://www.nhi.gov.tw/', '2026-10-30'),
  ('JP', 'Japan', 'My Number card tap-to-consent at point of care (70.43% of presenting patients, Jul 2026)',
   'My Number card / smartphone My Number', 'JP Core (FHIR R4)', 'NGSP', 'mg/dL',
   'point-of-care', 'The only deployed "tap for consent": identity, purpose-bound consent and record access in one gesture.',
   'https://www.mhlw.go.jp/', '2026-11-02')
on conflict (code) do update set regime = excluded.regime, access_status = excluded.access_status, access_note = excluded.access_note;

-- Cross-border corridors: people with records in two systems (Eurostat migr_pop1ctz, citizenship basis; understates dual nationals).
create table if not exists corridors (
  origin       char(2) not null references jurisdictions (code),
  destination  char(2) not null,
  residents    integer,
  reference_year smallint,
  source       text,
  primary key (origin, destination)
);
insert into corridors (origin, destination, residents, reference_year, source) values
  ('GB','ES',266462,2025,'Eurostat migr_pop1ctz'), ('GB','IE',91315,2025,'Eurostat migr_pop1ctz'),
  ('GB','DE',65691,2025,'Eurostat migr_pop1ctz'),  ('GB','PT',46341,2024,'Eurostat migr_pop1ctz'),
  ('GB','NL',44520,2025,'Eurostat migr_pop1ctz'),  ('US','DE',110391,2025,'Eurostat migr_pop1ctz'),
  ('US','ES',57379,2025,'Eurostat migr_pop1ctz'),  ('US','NL',26110,2025,'Eurostat migr_pop1ctz'),
  ('US','IE',20556,2025,'Eurostat migr_pop1ctz')
on conflict do nothing;

alter table providers add column if not exists jurisdiction char(2) references jurisdictions (code);
update providers set jurisdiction = country where jurisdiction is null and country in (select code from jurisdictions);

alter table jurisdictions enable row level security;
alter table corridors enable row level security;
drop policy if exists jurisdictions_read on jurisdictions;
create policy jurisdictions_read on jurisdictions for select to anon, authenticated using (true);
drop policy if exists corridors_read on corridors;
create policy corridors_read on corridors for select to anon, authenticated using (true);

-- ---------------------------------------------------------------------------
-- 2. Drug concepts: canonical ingredient + crosswalk
-- ---------------------------------------------------------------------------
create table if not exists drug_concepts (
  rxcui         text primary key,                   -- RxNorm ingredient concept
  ingredient    text not null unique,               -- lowercase canonical name
  atc           text,                               -- WHO ATC code
  dmd_vtm       text,                               -- NHS dm+d Virtual Therapeutic Moiety (SNOMED CT)
  canonical_unit text not null,                     -- dose unit all providers are converted to
  synonyms      text[] not null default '{}'        -- brand / regional spellings, lowercase
);
insert into drug_concepts (rxcui, ingredient, atc, dmd_vtm, canonical_unit, synonyms) values
  ('29046',   'lisinopril',    'C09AA03', '318859000', 'mg',  '{zestril,prinivil,lisinopril tablets}'),
  ('6809',    'metformin',     'A10BA02', '109081006', 'mg',  '{glucophage,metformin hydrochloride}'),
  ('83367',   'atorvastatin',  'C10AA05', '108597004', 'mg',  '{lipitor}'),
  ('17767',   'amlodipine',    'C08CA01', '108537001', 'mg',  '{norvasc,istin}'),
  ('10582',   'levothyroxine', 'H03AA01', '108944001', 'mcg', '{synthroid,levothyroxine sodium,eltroxin}'),
  ('7646',    'omeprazole',    'A02BC01', '108666005', 'mg',  '{losec,prilosec}'),
  ('435',     'salbutamol',    'R03AC02', '372897005', 'mcg', '{albuterol,ventolin,salbutamol inhaler}'),
  ('36437',   'sertraline',    'N06AB06', '108717008', 'mg',  '{zoloft,lustral}'),
  ('5640',    'ibuprofen',     'M01AE01', '387207008', 'mg',  '{advil,nurofen,motrin}'),
  ('1364430', 'apixaban',      'B01AF02', '698871007', 'mg',  '{eliquis}')
on conflict (rxcui) do update set synonyms = excluded.synonyms, dmd_vtm = excluded.dmd_vtm, atc = excluded.atc;

-- Resolve any provider spelling to a canonical concept. Code first, then name, then synonym.
create or replace function resolve_drug(p_rxnorm text, p_name text, p_display text)
returns drug_concepts language sql stable set search_path = public as $$
  select d.* from drug_concepts d
  where d.rxcui = p_rxnorm
     or d.ingredient = lower(p_name)
     or lower(p_display) = any(d.synonyms)
     or lower(p_display) like d.ingredient || '%'
  order by (d.rxcui = p_rxnorm) desc, (d.ingredient = lower(p_name)) desc
  limit 1;
$$;

-- Dose unit conversion to the concept's canonical unit.
create or replace function dose_to_canonical(v numeric, u text, canonical text) returns numeric
language sql immutable as $$
  select case
    when v is null or u is null then null
    when lower(u) = lower(canonical) then v
    when lower(u) = 'mg'  and canonical = 'mcg' then v * 1000
    when lower(u) in ('mcg','µg','ug') and canonical = 'mg' then v / 1000
    when lower(u) = 'g'   and canonical = 'mg'  then v * 1000
    else null  -- incompatible; surfaces as its own finding
  end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Lab unit conversions (LOINC + UCUM → canonical). Factor, or affine (a·x + b).
-- ---------------------------------------------------------------------------
create table if not exists unit_conversions (
  loinc_code     text not null,
  from_unit      text not null,                     -- UCUM as providers send it
  to_unit        text not null,                     -- canonical for display/comparison
  factor         numeric not null default 1,
  offset_add     numeric not null default 0,        -- canonical = factor * x + offset_add
  convention     text,                              -- e.g. IFCC→NGSP
  primary key (loinc_code, from_unit)
);
insert into unit_conversions (loinc_code, from_unit, to_unit, factor, offset_add, convention) values
  ('4548-4', 'mmol/mol', '%',     0.09148, 2.152, 'IFCC → NGSP (HbA1c master equation)'),
  ('4548-4', '%',        '%',     1,       0,     null),
  ('2345-7', 'mmol/L',   'mg/dL', 18.016,  0,     'glucose'),
  ('2345-7', 'mg/dL',    'mg/dL', 1,       0,     null),
  ('2093-3', 'mmol/L',   'mg/dL', 38.67,   0,     'cholesterol'),
  ('2093-3', 'mg/dL',    'mg/dL', 1,       0,     null),
  ('2160-0', 'µmol/L',   'mg/dL', 0.011312,0,     'creatinine'),
  ('2160-0', 'umol/L',   'mg/dL', 0.011312,0,     'creatinine'),
  ('2160-0', 'mg/dL',    'mg/dL', 1,       0,     null),
  ('718-7',  'g/L',      'g/dL',  0.1,     0,     'haemoglobin'),
  ('718-7',  'g/dL',     'g/dL',  1,       0,     null),
  ('3016-3', 'mIU/L',    'mIU/L', 1,       0,     null),
  ('3016-3', 'uIU/mL',   'mIU/L', 1,       0,     'TSH (equal)')
on conflict (loinc_code, from_unit) do update set factor = excluded.factor, offset_add = excluded.offset_add, to_unit = excluded.to_unit;

alter table drug_concepts enable row level security;
alter table unit_conversions enable row level security;
drop policy if exists drug_concepts_read on drug_concepts;
create policy drug_concepts_read on drug_concepts for select to anon, authenticated using (true);
drop policy if exists unit_conversions_read on unit_conversions;
create policy unit_conversions_read on unit_conversions for select to anon, authenticated using (true);

-- ---------------------------------------------------------------------------
-- 4. Canonical views (security_invoker: RLS of the base tables applies)
-- ---------------------------------------------------------------------------
create or replace view medications_canonical with (security_invoker = true) as
select m.*,
       d.rxcui         as canonical_rxcui,
       d.ingredient    as canonical_ingredient,
       d.atc           as canonical_atc,
       d.canonical_unit,
       dose_to_canonical(m.dose_value, m.dose_unit, d.canonical_unit) as canonical_dose,
       pr.jurisdiction as source_jurisdiction
from medications m
join providers pr on pr.id = m.provider_id
left join lateral resolve_drug(m.rxnorm_code, m.name, m.display_name) d on true;

create or replace view observations_canonical with (security_invoker = true) as
select o.*,
       coalesce(uc.to_unit, o.unit)                                   as canonical_unit,
       case when uc.loinc_code is null then o.value
            else round((o.value * uc.factor + uc.offset_add)::numeric, 2) end as canonical_value,
       uc.convention,
       pr.jurisdiction as source_jurisdiction
from observations o
join providers pr on pr.id = o.provider_id
left join unit_conversions uc on uc.loinc_code = o.loinc_code and uc.from_unit = o.unit;

grant select on medications_canonical, observations_canonical to authenticated;

-- ---------------------------------------------------------------------------
-- 5. detect_discrepancies(): code-based dose conflicts + unit mismatch rule
-- ---------------------------------------------------------------------------
create or replace function detect_discrepancies(p uuid)
returns table (
  kind discrepancy_kind, severity severity, record_table text,
  record_ids uuid[], provider_ids uuid[], fingerprint text, summary text, detail jsonb
)
language sql stable security definer set search_path = public as $$
  -- 1. Dose conflicts on the CANONICAL ingredient and CANONICAL unit.
  with active_meds as (
    select m.*, pr.short_name as provider_name, pr.jurisdiction
    from medications_canonical m join providers pr on pr.id = m.provider_id
    where m.patient_id = p and m.status = 'active'
  ),
  dose_conflicts as (
    select coalesce(a.canonical_ingredient, a.name) as ingredient, max(a.canonical_rxcui) as rxcui,
           array_agg(a.id order by a.recorded_at desc)          as ids,
           array_agg(a.provider_id order by a.recorded_at desc) as prov,
           jsonb_agg(jsonb_build_object(
             'id', a.id, 'provider', a.provider_name, 'provider_id', a.provider_id, 'jurisdiction', a.jurisdiction,
             'display_name', a.display_name, 'dose', a.dose_text,
             'dose_value', a.dose_value, 'dose_unit', a.dose_unit,
             'canonical_dose', a.canonical_dose, 'canonical_unit', a.canonical_unit,
             'recorded_at', a.recorded_at) order by a.recorded_at desc)   as sources
    from active_meds a
    group by coalesce(a.canonical_ingredient, a.name)
    having count(distinct a.provider_id) >= 2
       and count(distinct coalesce(a.canonical_dose::text, a.dose_value::text || a.dose_unit)) >= 2
  )
  select 'dose_conflict'::discrepancy_kind, 'high'::severity, 'medications',
         ids, prov, 'dose_conflict:' || ingredient,
         format('%s providers disagree on the %s dose', cardinality(prov), initcap(ingredient)),
         jsonb_build_object('drug', ingredient, 'rxcui', rxcui, 'sources', sources)
  from dose_conflicts

  union all
  -- 2. Missing allergy across connected providers.
  select 'missing_allergy', case when max(a.criticality) = 'high' then 'critical' else 'medium' end::severity,
         'allergies', array_agg(a.id), array_agg(a.provider_id) || pp.provider_id,
         'missing_allergy:' || a.substance || ':' || pp.provider_id,
         format('%s allergy is on file at %s but missing at %s', initcap(a.substance), string_agg(src.short_name, ' and '), miss.short_name),
         jsonb_build_object('substance', a.substance, 'criticality', max(a.criticality),
                            'known_at', jsonb_agg(jsonb_build_object('id', a.id, 'provider', src.short_name, 'provider_id', a.provider_id,
                                                                     'reaction', a.reaction, 'recorded_at', a.recorded_at)),
                            'missing_at', miss.short_name, 'missing_at_id', pp.provider_id)
  from allergies a
  join providers src on src.id = a.provider_id
  join patient_providers pp on pp.patient_id = a.patient_id and pp.provider_id <> a.provider_id
  join providers miss on miss.id = pp.provider_id
  where a.patient_id = p
    and not exists (select 1 from allergies b where b.patient_id = p and b.provider_id = pp.provider_id and b.substance = a.substance)
  group by a.substance, pp.provider_id, miss.short_name

  union all
  -- 3. Stale medication.
  select 'stale_medication', 'medium', 'medications', array[m.id], array[m.provider_id],
         'stale_medication:' || m.id,
         format('%s at %s has not been reviewed since %s', m.display_name, pr.short_name, to_char(m.recorded_at, 'Mon YYYY')),
         jsonb_build_object('drug', m.name, 'display_name', m.display_name, 'provider', pr.short_name,
                            'provider_id', m.provider_id, 'recorded_at', m.recorded_at,
                            'months_stale', floor(extract(epoch from now() - m.recorded_at) / 2629800))
  from medications m join providers pr on pr.id = m.provider_id
  where m.patient_id = p and m.status = 'active' and m.ended_on is null
    and m.recorded_at < now() - interval '24 months'

  union all
  -- 4. Incomplete provider.
  select 'incomplete_provider', 'low', 'providers', '{}'::uuid[], array[pr.id],
         'incomplete_provider:' || pr.id,
         format('%s has no NPI or ODS identifier on record', pr.name),
         jsonb_build_object('provider', pr.name, 'provider_id', pr.id, 'missing', array['npi','ods_code'])
  from patient_providers pp join providers pr on pr.id = pp.provider_id
  where pp.patient_id = p and pr.npi is null and pr.ods_code is null

  union all
  -- 5. Conflicting condition status.
  select 'conflicting_status', 'medium', 'conditions',
         array_agg(c.id), array_agg(c.provider_id),
         'conflicting_status:' || c.name,
         format('%s is %s at one provider and %s at another', initcap(c.name), min(c.clinical_status), max(c.clinical_status)),
         jsonb_build_object('condition', c.name, 'sources', jsonb_agg(jsonb_build_object(
            'id', c.id, 'provider', pr.short_name, 'provider_id', c.provider_id,
            'status', c.clinical_status, 'recorded_at', c.recorded_at)))
  from conditions c join providers pr on pr.id = c.provider_id
  where c.patient_id = p
  group by c.name
  having count(distinct c.clinical_status) >= 2

  union all
  -- 6. Duplicate record at the same provider.
  select 'duplicate_record', 'low', 'medications', array_agg(m.id), array[m.provider_id],
         'duplicate_record:' || m.provider_id || ':' || m.name,
         format('%s is listed %s times at %s', initcap(m.name), count(*), pr.short_name),
         jsonb_build_object('drug', m.name, 'provider', pr.short_name, 'count', count(*))
  from medications m join providers pr on pr.id = m.provider_id
  where m.patient_id = p and m.status = 'active'
  group by m.provider_id, m.name, pr.short_name
  having count(*) >= 2

  union all
  -- 7. Unit mismatch: same LOINC at ≥2 providers in units Consentra cannot reconcile.
  select 'unit_mismatch', 'medium', 'observations', array_agg(o.id), array_agg(distinct o.provider_id),
         'unit_mismatch:' || o.loinc_code,
         format('%s is reported in %s across sources with no conversion on file', max(o.name), string_agg(distinct o.unit, ' and ')),
         jsonb_build_object('loinc', o.loinc_code, 'units', array_agg(distinct o.unit))
  from observations o
  left join unit_conversions uc on uc.loinc_code = o.loinc_code and uc.from_unit = o.unit
  where o.patient_id = p
  group by o.loinc_code
  having count(distinct o.unit) >= 2 and bool_or(uc.loinc_code is null);
$$;
revoke all on function detect_discrepancies(uuid) from public;
grant execute on function detect_discrepancies(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Cohort-scale view for the pitch: how many records would be reconciled per
-- jurisdiction pair if every corridor patient connected both systems.
-- ---------------------------------------------------------------------------
create or replace view normalization_coverage with (security_invoker = true) as
select pr.jurisdiction, j.hba1c_convention, j.glucose_unit,
       count(distinct o.id) filter (where uc.loinc_code is not null) as observations_convertible,
       count(distinct o.id)                                           as observations_total,
       count(distinct m.id) filter (where d.rxcui is not null)       as medications_coded,
       count(distinct m.id)                                           as medications_total
from providers pr
join jurisdictions j on j.code = pr.jurisdiction
left join observations o on o.provider_id = pr.id
left join unit_conversions uc on uc.loinc_code = o.loinc_code and uc.from_unit = o.unit
left join medications m on m.provider_id = pr.id
left join lateral resolve_drug(m.rxnorm_code, m.name, m.display_name) d on true
group by pr.jurisdiction, j.hba1c_convention, j.glucose_unit;
grant select on normalization_coverage to authenticated;

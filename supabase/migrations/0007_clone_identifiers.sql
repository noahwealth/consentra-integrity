-- Consentra · Migration 0007: make cloned identifiers valid and unique
--
-- Sodabase's second scan found 6 findings that are all one root cause: the per-visitor
-- clone in 0005 derived new identifiers in ways that break format or uniqueness.
--
--   source_id   invalid format   medications 9, observations 9, conditions 6, allergies 5,
--                                immunizations 3
--               0005 appended '/<uid8>', producing "MedicationStatement/6755eab2/a1b2c3d4".
--               The column is FHIR "ResourceType/id" shaped — one slash — so every cloned
--               row reads as malformed. Fixed to "<ResourceType>/<id>-<uid8>".
--   external_id duplicate        patient_providers 3
--               0005 copied external_id verbatim, so every clone collides with the template.
--
-- This matters more than its row counts suggest: the counts GROW with every visitor, so
-- the data-quality verdict degrades precisely while judges are using the app.
--
-- Idempotent: the UPDATEs are shape-guarded and the function is CREATE OR REPLACE.

-- ---------------------------------------------------------------------------
-- 1. Repair identifiers on clones that already exist.
-- ---------------------------------------------------------------------------
-- "Type/id/suffix" -> "Type/id-suffix". Rows with a single slash are left alone.
update medications   set source_id = regexp_replace(source_id, '^([^/]+/[^/]+)/(.+)$', '\1-\2') where source_id ~ '^[^/]+/[^/]+/.+$';
update allergies     set source_id = regexp_replace(source_id, '^([^/]+/[^/]+)/(.+)$', '\1-\2') where source_id ~ '^[^/]+/[^/]+/.+$';
update conditions    set source_id = regexp_replace(source_id, '^([^/]+/[^/]+)/(.+)$', '\1-\2') where source_id ~ '^[^/]+/[^/]+/.+$';
update observations  set source_id = regexp_replace(source_id, '^([^/]+/[^/]+)/(.+)$', '\1-\2') where source_id ~ '^[^/]+/[^/]+/.+$';
update immunizations set source_id = regexp_replace(source_id, '^([^/]+/[^/]+)/(.+)$', '\1-\2') where source_id ~ '^[^/]+/[^/]+/.+$';

-- Give every non-template patient_providers row an external_id unique to its patient.
update patient_providers pp
   set external_id = pp.external_id || '-' || left(replace(pp.patient_id::text, '-', ''), 8)
 where exists (select 1 from patients p where p.id = pp.patient_id and p.is_demo = false)
   and pp.external_id is not null
   and pp.external_id not like '%-' || left(replace(pp.patient_id::text, '-', ''), 8);

-- ---------------------------------------------------------------------------
-- 2. Stop producing them: the clone now derives identifiers correctly.
--    Identical to 0005 except sfx is '-' (keeping source_id single-slash) and
--    patient_providers.external_id carries the same suffix.
-- ---------------------------------------------------------------------------
create or replace function claim_demo_patient() returns patients
language plpgsql security definer set search_path = public as $$
declare tmpl patients; p patients; sfx text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select * into p from patients where auth_user_id = auth.uid();
  if found then return p; end if;

  select * into tmpl from patients where is_demo and auth_user_id is null order by created_at limit 1;
  if not found then
    select * into tmpl from patients where is_demo order by created_at limit 1;
    if not found then raise exception 'no demo patient seeded'; end if;
    update patients set auth_user_id = null where id = tmpl.id;
  end if;

  -- '-' not '/': source_id must stay FHIR "ResourceType/id" shaped.
  sfx := '-' || left(replace(auth.uid()::text, '-', ''), 8);

  insert into patients (auth_user_id, given_name, family_name, birth_date, sex, nhs_number, mrn, home_country, is_demo)
  values (auth.uid(), tmpl.given_name, tmpl.family_name, tmpl.birth_date, tmpl.sex, tmpl.nhs_number, tmpl.mrn, tmpl.home_country, false)
  returning * into p;

  insert into patient_providers (patient_id, provider_id, external_id, connected_at, last_synced)
  select p.id, provider_id, external_id || sfx, connected_at, last_synced from patient_providers where patient_id = tmpl.id;

  insert into medications (patient_id, provider_id, source_id, rxnorm_code, name, display_name, dose_value, dose_unit, dose_text, frequency, route, status, started_on, ended_on, recorded_at, fhir)
  select p.id, provider_id, source_id || sfx, rxnorm_code, name, display_name, dose_value, dose_unit, dose_text, frequency, route, status, started_on, ended_on, recorded_at, fhir
  from medications where patient_id = tmpl.id;

  insert into allergies (patient_id, provider_id, source_id, substance, display_name, criticality, reaction, verification, recorded_at, fhir)
  select p.id, provider_id, source_id || sfx, substance, display_name, criticality, reaction, verification, recorded_at, fhir
  from allergies where patient_id = tmpl.id;

  insert into conditions (patient_id, provider_id, source_id, icd10_code, name, display_name, clinical_status, onset_on, abated_on, recorded_at, fhir)
  select p.id, provider_id, source_id || sfx, icd10_code, name, display_name, clinical_status, onset_on, abated_on, recorded_at, fhir
  from conditions where patient_id = tmpl.id;

  insert into observations (patient_id, provider_id, source_id, loinc_code, name, value, unit, reference_low, reference_high, observed_at, recorded_at, fhir)
  select p.id, provider_id, source_id || sfx, loinc_code, name, value, unit, reference_low, reference_high, observed_at, recorded_at, fhir
  from observations where patient_id = tmpl.id;

  insert into immunizations (patient_id, provider_id, source_id, cvx_code, name, occurred_on, recorded_at, fhir)
  select p.id, provider_id, source_id || sfx, cvx_code, name, occurred_on, recorded_at, fhir
  from immunizations where patient_id = tmpl.id;

  return p;
end $$;
revoke all on function claim_demo_patient() from public;
grant execute on function claim_demo_patient() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Guard: no malformed source_id may remain.
-- ---------------------------------------------------------------------------
do $$
declare bad int;
begin
  select (select count(*) from medications   where source_id ~ '^[^/]+/[^/]+/.+$')
       + (select count(*) from allergies     where source_id ~ '^[^/]+/[^/]+/.+$')
       + (select count(*) from conditions    where source_id ~ '^[^/]+/[^/]+/.+$')
       + (select count(*) from observations  where source_id ~ '^[^/]+/[^/]+/.+$')
       + (select count(*) from immunizations where source_id ~ '^[^/]+/[^/]+/.+$') into bad;
  if bad > 0 then raise exception 'malformed source_id rows remain: %', bad; end if;
end $$;

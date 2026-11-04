-- Consentra · Health Data Integrity
-- Migration 0001: schema, indexes, RLS, RPCs, discrepancy detection.
--
-- Design notes
--   * Every clinical table carries (patient_id, provider_id). One patient, many
--     providers, so the same fact can exist several times and disagree. That is
--     the whole point: Consentra reconciles across sources.
--   * Columns are FHIR R4-shaped (MedicationStatement, AllergyIntolerance,
--     Condition, Observation) but flattened for querying. `fhir` keeps the
--     original resource JSON so nothing is lost.
--   * RLS: a patient reads and writes only their own rows via auth.uid().
--     Clinicians never log in; they get a time-boxed share token resolved by a
--     SECURITY DEFINER function that returns only the shared categories.
--   * Sodabase watches these tables through its own read-only role. It is
--     granted SELECT on the public schema at connect time by Sodabase itself.

-- pgcrypto: hosted Supabase installs extensions into the `extensions` schema, so
-- gen_random_bytes is referenced schema-qualified below. The schema already exists
-- on hosted Supabase (this is a no-op there); creating it first is what keeps the
-- same file working on plain Postgres, where `with schema extensions` would
-- otherwise fail with 'schema "extensions" does not exist'.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type record_status as enum ('active', 'completed', 'stopped', 'entered-in-error', 'unknown');
exception when duplicate_object then null; end $$;

do $$ begin
  create type discrepancy_kind as enum (
    'dose_conflict',          -- same drug, different dose across providers
    'missing_allergy',        -- allergy known at one provider, absent at another
    'stale_medication',       -- active med not touched in > 24 months
    'incomplete_provider',    -- provider record missing identifiers
    'duplicate_record',       -- same fact recorded twice at the same provider
    'conflicting_status',     -- condition active at one provider, resolved at another
    'unit_mismatch',          -- same lab, incompatible units
    'table_trust',            -- table-level verdict from Sodabase
    'rule_breach'             -- plain-language rule checked by Sodabase
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type discrepancy_status as enum ('open', 'flagged', 'resolved', 'dismissed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type severity as enum ('low', 'medium', 'high', 'critical');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Core tables
-- ---------------------------------------------------------------------------
create table if not exists providers (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  short_name    text not null,
  country       char(2) not null,
  city          text,
  npi           text,                       -- nullable on purpose: one seeded provider lacks it
  ods_code      text,                       -- UK equivalent
  fhir_base_url text,
  ehr_vendor    text,
  created_at    timestamptz not null default now()
);

create table if not exists patients (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid unique references auth.users (id) on delete set null,
  given_name    text not null,
  family_name   text not null,
  birth_date    date not null,
  sex           text,
  nhs_number    text,
  mrn           text,
  home_country  char(2),
  is_demo       boolean not null default false,
  created_at    timestamptz not null default now()
);

create table if not exists patient_providers (
  patient_id    uuid not null references patients (id) on delete cascade,
  provider_id   uuid not null references providers (id) on delete cascade,
  external_id   text,                       -- the patient's id inside that EHR
  connected_at  timestamptz not null default now(),
  last_synced   timestamptz,
  primary key (patient_id, provider_id)
);

create table if not exists medications (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients (id) on delete cascade,
  provider_id      uuid not null references providers (id),
  source_id        text not null,           -- resource id at the provider
  rxnorm_code      text,
  name             text not null,           -- generic name, lowercased for matching
  display_name     text not null,           -- as shown by the provider (brand/generic)
  dose_value       numeric,
  dose_unit        text,
  dose_text        text,
  frequency        text,
  route            text,
  status           record_status not null default 'active',
  started_on       date,
  ended_on         date,
  recorded_at      timestamptz not null,    -- when the provider last touched it
  fhir             jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (provider_id, source_id)
);

create table if not exists allergies (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients (id) on delete cascade,
  provider_id      uuid not null references providers (id),
  source_id        text not null,
  substance        text not null,           -- lowercased for matching
  display_name     text not null,
  criticality      text,                    -- low | high | unable-to-assess
  reaction         text,
  verification     text,                    -- confirmed | unconfirmed | refuted
  recorded_at      timestamptz not null,
  fhir             jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (provider_id, source_id)
);

create table if not exists conditions (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients (id) on delete cascade,
  provider_id      uuid not null references providers (id),
  source_id        text not null,
  icd10_code       text,
  name             text not null,
  display_name     text not null,
  clinical_status  text not null,           -- active | resolved | remission | inactive
  onset_on         date,
  abated_on        date,
  recorded_at      timestamptz not null,
  fhir             jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (provider_id, source_id)
);

create table if not exists observations (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients (id) on delete cascade,
  provider_id      uuid not null references providers (id),
  source_id        text not null,
  loinc_code       text,
  name             text not null,
  value            numeric,
  unit             text,
  reference_low    numeric,
  reference_high   numeric,
  observed_at      timestamptz not null,
  recorded_at      timestamptz not null,
  fhir             jsonb,
  created_at       timestamptz not null default now(),
  unique (provider_id, source_id)
);

create table if not exists immunizations (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients (id) on delete cascade,
  provider_id      uuid not null references providers (id),
  source_id        text not null,
  cvx_code         text,
  name             text not null,
  occurred_on      date not null,
  recorded_at      timestamptz not null,
  fhir             jsonb,
  created_at       timestamptz not null default now(),
  unique (provider_id, source_id)
);

-- ---------------------------------------------------------------------------
-- Integrity layer
-- ---------------------------------------------------------------------------
create table if not exists integrity_scans (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients (id) on delete cascade,
  started_at       timestamptz not null default now(),
  finished_at      timestamptz,
  sodabase_ok      boolean,                 -- did the Sodabase call succeed
  summary          jsonb not null default '{}'::jsonb,
  created_by       uuid references auth.users (id)
);

create table if not exists discrepancies (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients (id) on delete cascade,
  scan_id          uuid references integrity_scans (id) on delete set null,
  kind             discrepancy_kind not null,
  severity         severity not null default 'medium',
  status           discrepancy_status not null default 'open',
  record_table     text not null,           -- medications | allergies | ...
  record_ids       uuid[] not null default '{}',
  provider_ids     uuid[] not null default '{}',
  fingerprint      text not null,           -- stable key so re-scans upsert, not duplicate
  summary          text not null,
  detail           jsonb not null default '{}'::jsonb,
  detected_by      text not null default 'consentra',   -- consentra | sodabase
  sodabase_finding text,                    -- finding id when detected_by = sodabase
  flagged_at       timestamptz,
  flagged_note     text,
  resolved_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (patient_id, fingerprint)
);

create table if not exists shares (
  id                  uuid primary key default gen_random_uuid(),
  patient_id          uuid not null references patients (id) on delete cascade,
  token               text not null unique default translate(encode(extensions.gen_random_bytes(16), 'base64'), '+/=', '-_'),
  label               text not null default '',
  categories          text[] not null,      -- medications | allergies | conditions | observations | immunizations
  include_unresolved  boolean not null default true,  -- show flagged discrepancies to the clinician
  created_at          timestamptz not null default now(),
  expires_at          timestamptz not null,
  revoked_at          timestamptz,
  view_count          integer not null default 0,
  last_viewed_at      timestamptz
);

alter table shares alter column token set default translate(encode(extensions.gen_random_bytes(16), 'base64'), '+/=', '-_');

create table if not exists share_views (
  id          bigint generated always as identity primary key,
  share_id    uuid not null references shares (id) on delete cascade,
  viewed_at   timestamptz not null default now(),
  user_agent  text
);

-- ---------------------------------------------------------------------------
-- Indexes (every patient-scoped query hits patient_id first)
-- ---------------------------------------------------------------------------
create index if not exists medications_patient_idx   on medications (patient_id, name);
create index if not exists medications_recorded_idx  on medications (recorded_at);
create index if not exists allergies_patient_idx     on allergies (patient_id, substance);
create index if not exists conditions_patient_idx    on conditions (patient_id, name);
create index if not exists observations_patient_idx  on observations (patient_id, loinc_code, observed_at desc);
create index if not exists immunizations_patient_idx on immunizations (patient_id);
create index if not exists discrepancies_patient_idx on discrepancies (patient_id, status);
create index if not exists shares_token_idx          on shares (token);
create index if not exists shares_patient_idx        on shares (patient_id, created_at desc);
create index if not exists scans_patient_idx         on integrity_scans (patient_id, started_at desc);

-- updated_at trigger
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$ declare t text; begin
  foreach t in array array['medications','allergies','conditions','discrepancies'] loop
    execute format('drop trigger if exists %I_updated_at on %I', t, t);
    execute format('create trigger %I_updated_at before update on %I for each row execute function set_updated_at()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table providers         enable row level security;
alter table patients          enable row level security;
alter table patient_providers enable row level security;
alter table medications       enable row level security;
alter table allergies         enable row level security;
alter table conditions        enable row level security;
alter table observations      enable row level security;
alter table immunizations     enable row level security;
alter table integrity_scans   enable row level security;
alter table discrepancies     enable row level security;
alter table shares            enable row level security;
alter table share_views       enable row level security;

-- Providers are a public directory.
drop policy if exists providers_read on providers;
create policy providers_read on providers for select to authenticated, anon using (true);

-- A patient sees exactly their own row.
drop policy if exists patients_self on patients;
create policy patients_self on patients for select to authenticated using (auth_user_id = auth.uid());

-- Helper: does the current user own this patient?
create or replace function owns_patient(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from patients where id = p and auth_user_id = auth.uid());
$$;

do $$ declare t text; begin
  foreach t in array array['patient_providers','medications','allergies','conditions','observations','immunizations','integrity_scans'] loop
    execute format('drop policy if exists %I_owner on %I', t, t);
    execute format('create policy %I_owner on %I for select to authenticated using (owns_patient(patient_id))', t, t);
  end loop;
end $$;

-- Discrepancies: read own; update own (flag / resolve / dismiss) but never insert
-- from the client; the scan function writes them.
drop policy if exists discrepancies_read on discrepancies;
create policy discrepancies_read on discrepancies for select to authenticated using (owns_patient(patient_id));
drop policy if exists discrepancies_update on discrepancies;
create policy discrepancies_update on discrepancies for update to authenticated
  using (owns_patient(patient_id)) with check (owns_patient(patient_id));

-- Shares: full control over own shares.
drop policy if exists shares_owner on shares;
create policy shares_owner on shares for all to authenticated
  using (owns_patient(patient_id)) with check (owns_patient(patient_id));
drop policy if exists share_views_owner on share_views;
create policy share_views_owner on share_views for select to authenticated
  using (exists (select 1 from shares s where s.id = share_id and owns_patient(s.patient_id)));

-- ---------------------------------------------------------------------------
-- RPC: claim the demo patient (anonymous sign-in → Noah Dixon)
-- ---------------------------------------------------------------------------
create or replace function claim_demo_patient() returns patients
language plpgsql security definer set search_path = public as $$
declare p patients;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  -- Already own a patient? return it.
  select * into p from patients where auth_user_id = auth.uid();
  if found then return p; end if;
  -- Otherwise take over the demo patient. Single-tenant by design for the demo.
  update patients set auth_user_id = auth.uid() where is_demo = true returning * into p;
  if not found then raise exception 'no demo patient seeded'; end if;
  return p;
end $$;
revoke all on function claim_demo_patient() from public;
grant execute on function claim_demo_patient() to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: patient record bundle (one round trip for the Passport screen)
-- ---------------------------------------------------------------------------
create or replace function my_record() returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'patient',       (select to_jsonb(p) from patients p where p.auth_user_id = auth.uid()),
    'providers',     (select coalesce(jsonb_agg(to_jsonb(pr) || jsonb_build_object('last_synced', pp.last_synced)), '[]'::jsonb)
                        from patient_providers pp join providers pr on pr.id = pp.provider_id
                        where owns_patient(pp.patient_id)),
    'medications',   (select coalesce(jsonb_agg(to_jsonb(m) order by m.name, m.recorded_at desc), '[]'::jsonb) from medications m where owns_patient(m.patient_id)),
    'allergies',     (select coalesce(jsonb_agg(to_jsonb(a) order by a.substance), '[]'::jsonb) from allergies a where owns_patient(a.patient_id)),
    'conditions',    (select coalesce(jsonb_agg(to_jsonb(c) order by c.name), '[]'::jsonb) from conditions c where owns_patient(c.patient_id)),
    'observations',  (select coalesce(jsonb_agg(to_jsonb(o) order by o.observed_at desc), '[]'::jsonb) from observations o where owns_patient(o.patient_id)),
    'immunizations', (select coalesce(jsonb_agg(to_jsonb(i) order by i.occurred_on desc), '[]'::jsonb) from immunizations i where owns_patient(i.patient_id)),
    'discrepancies', (select coalesce(jsonb_agg(to_jsonb(d) order by d.severity desc, d.created_at desc), '[]'::jsonb) from discrepancies d where owns_patient(d.patient_id)),
    'last_scan',     (select to_jsonb(s) from integrity_scans s where owns_patient(s.patient_id) order by s.started_at desc limit 1)
  );
$$;
grant execute on function my_record() to authenticated;

-- ---------------------------------------------------------------------------
-- Discrepancy detection (Consentra rules). Runs as the scan service.
-- Returns rows; the edge function upserts them with scan_id.
-- ---------------------------------------------------------------------------
create or replace function detect_discrepancies(p uuid)
returns table (
  kind discrepancy_kind, severity severity, record_table text,
  record_ids uuid[], provider_ids uuid[], fingerprint text, summary text, detail jsonb
)
language sql stable security definer set search_path = public as $$
  -- 1. Dose conflicts: same generic name, active at ≥2 providers, different dose.
  with active_meds as (
    select m.*, pr.short_name as provider_name
    from medications m join providers pr on pr.id = m.provider_id
    where m.patient_id = p and m.status = 'active'
  ),
  dose_conflicts as (
    select a.name,
           array_agg(a.id order by a.recorded_at desc)          as ids,
           array_agg(a.provider_id order by a.recorded_at desc) as prov,
           jsonb_agg(jsonb_build_object(
             'id', a.id, 'provider', a.provider_name, 'provider_id', a.provider_id,
             'display_name', a.display_name, 'dose', a.dose_text,
             'dose_value', a.dose_value, 'dose_unit', a.dose_unit,
             'recorded_at', a.recorded_at) order by a.recorded_at desc)   as sources
    from active_meds a
    group by a.name
    having count(distinct a.provider_id) >= 2
       and count(distinct coalesce(a.dose_value::text,'') || coalesce(a.dose_unit,'')) >= 2
  )
  select 'dose_conflict'::discrepancy_kind, 'high'::severity, 'medications',
         ids, prov, 'dose_conflict:' || name,
         format('%s providers disagree on the %s dose', cardinality(prov), initcap(name)),
         jsonb_build_object('drug', name, 'sources', sources)
  from dose_conflicts

  union all
  -- 2. Missing allergy: recorded at one provider, absent at another connected provider.
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
  -- 3. Stale medication: active, no end date, untouched for > 24 months.
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
  -- 4. Incomplete provider: a connected provider with no identifier at all.
  select 'incomplete_provider', 'low', 'providers', '{}'::uuid[], array[pr.id],
         'incomplete_provider:' || pr.id,
         format('%s has no NPI or ODS identifier on record', pr.name),
         jsonb_build_object('provider', pr.name, 'provider_id', pr.id, 'missing', array['npi','ods_code'])
  from patient_providers pp join providers pr on pr.id = pp.provider_id
  where pp.patient_id = p and pr.npi is null and pr.ods_code is null

  union all
  -- 5. Conflicting condition status across providers.
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
  -- 6. Duplicate record at the same provider (same drug entered twice, both active).
  select 'duplicate_record', 'low', 'medications', array_agg(m.id), array[m.provider_id],
         'duplicate_record:' || m.provider_id || ':' || m.name,
         format('%s is listed %s times at %s', initcap(m.name), count(*), pr.short_name),
         jsonb_build_object('drug', m.name, 'provider', pr.short_name, 'count', count(*))
  from medications m join providers pr on pr.id = m.provider_id
  where m.patient_id = p and m.status = 'active'
  group by m.provider_id, m.name, pr.short_name
  having count(*) >= 2;
$$;
revoke all on function detect_discrepancies(uuid) from public;
grant execute on function detect_discrepancies(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- RPC (service only): upsert a batch of findings from a scan. Keeps the
-- patient's status on findings that already exist; auto-resolves findings of
-- the same detector that this scan no longer reports.
-- ---------------------------------------------------------------------------
create or replace function upsert_discrepancies(p uuid, scan uuid, detector text, findings jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  insert into discrepancies (patient_id, scan_id, kind, severity, record_table, record_ids, provider_ids,
                             fingerprint, summary, detail, detected_by, sodabase_finding)
  select p, scan, (f->>'kind')::discrepancy_kind, coalesce((f->>'severity')::severity, 'medium'),
         f->>'record_table',
         coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(coalesce(f->'record_ids','[]')) x), '{}'),
         coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(coalesce(f->'provider_ids','[]')) x), '{}'),
         f->>'fingerprint', f->>'summary', coalesce(f->'detail', '{}'::jsonb), detector, f->>'sodabase_finding'
  from jsonb_array_elements(findings) f
  on conflict (patient_id, fingerprint) do update
    set scan_id = excluded.scan_id, severity = excluded.severity, summary = excluded.summary,
        detail = excluded.detail, sodabase_finding = excluded.sodabase_finding,
        -- a finding that was auto-resolved but is back becomes open again
        status = case when discrepancies.status = 'resolved' and discrepancies.flagged_at is null then 'open' else discrepancies.status end;
  get diagnostics n = row_count;

  update discrepancies d set status = 'resolved', resolved_at = now()
   where d.patient_id = p and d.detected_by = detector and d.status in ('open','flagged')
     and d.fingerprint not in (select f->>'fingerprint' from jsonb_array_elements(findings) f);
  return n;
end $$;
revoke all on function upsert_discrepancies(uuid, uuid, text, jsonb) from public;
grant execute on function upsert_discrepancies(uuid, uuid, text, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- RPC: patient flags or resolves a discrepancy
-- ---------------------------------------------------------------------------
create or replace function set_discrepancy_status(d uuid, s discrepancy_status, note text default null)
returns discrepancies language plpgsql security invoker set search_path = public as $$
declare row discrepancies;
begin
  update discrepancies
     set status = s,
         flagged_at  = case when s = 'flagged'  then now() else flagged_at end,
         flagged_note = coalesce(note, flagged_note),
         resolved_at = case when s in ('resolved','dismissed') then now() else null end
   where id = d returning * into row;
  if not found then raise exception 'not found or not yours'; end if;
  return row;
end $$;
grant execute on function set_discrepancy_status(uuid, discrepancy_status, text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: clinician opens a share (no login). Returns only shared categories,
-- marks records touched by an open/flagged discrepancy, logs the view.
-- ---------------------------------------------------------------------------
create or replace function get_share(t text, ua text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s shares; pid uuid; out jsonb; flagged_ids uuid[];
begin
  select * into s from shares where token = t;
  if not found then return jsonb_build_object('status', 'not_found'); end if;
  if s.revoked_at is not null then return jsonb_build_object('status', 'revoked', 'label', s.label); end if;
  if s.expires_at < now() then return jsonb_build_object('status', 'expired', 'label', s.label); end if;

  pid := s.patient_id;
  update shares set view_count = view_count + 1, last_viewed_at = now() where id = s.id;
  insert into share_views (share_id, user_agent) values (s.id, ua);

  select coalesce(array_agg(x), '{}') into flagged_ids
  from discrepancies d, unnest(d.record_ids) x
  where d.patient_id = pid and d.status in ('open','flagged');

  out := jsonb_build_object(
    'status', 'active',
    'label', s.label,
    'expires_at', s.expires_at,
    'categories', s.categories,
    'include_unresolved', s.include_unresolved,
    'patient', (select jsonb_build_object('given_name', given_name, 'family_name', family_name,
                                          'birth_date', birth_date, 'home_country', home_country)
                from patients where id = pid),
    'providers', (select coalesce(jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.name, 'short_name', pr.short_name, 'country', pr.country)), '[]')
                  from patient_providers pp join providers pr on pr.id = pp.provider_id where pp.patient_id = pid),
    'last_scan', (select jsonb_build_object('finished_at', finished_at, 'summary', summary)
                  from integrity_scans where patient_id = pid and finished_at is not null order by started_at desc limit 1)
  );

  if 'medications' = any(s.categories) then
    out := out || jsonb_build_object('medications', (
      select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('flagged', m.id = any(flagged_ids)) order by m.name), '[]')
      from medications m where m.patient_id = pid));
  end if;
  if 'allergies' = any(s.categories) then
    out := out || jsonb_build_object('allergies', (
      select coalesce(jsonb_agg(to_jsonb(a) || jsonb_build_object('flagged', a.id = any(flagged_ids)) order by a.substance), '[]')
      from allergies a where a.patient_id = pid));
  end if;
  if 'conditions' = any(s.categories) then
    out := out || jsonb_build_object('conditions', (
      select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('flagged', c.id = any(flagged_ids)) order by c.name), '[]')
      from conditions c where c.patient_id = pid));
  end if;
  if 'observations' = any(s.categories) then
    out := out || jsonb_build_object('observations', (
      select coalesce(jsonb_agg(to_jsonb(o) order by o.observed_at desc), '[]')
      from observations o where o.patient_id = pid));
  end if;
  if 'immunizations' = any(s.categories) then
    out := out || jsonb_build_object('immunizations', (
      select coalesce(jsonb_agg(to_jsonb(i) order by i.occurred_on desc), '[]')
      from immunizations i where i.patient_id = pid));
  end if;
  if s.include_unresolved then
    out := out || jsonb_build_object('discrepancies', (
      select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'severity', d.severity, 'status', d.status,
                                                   'summary', d.summary, 'detail', d.detail, 'detected_by', d.detected_by,
                                                   'record_ids', d.record_ids, 'flagged_note', d.flagged_note)
                               order by d.severity desc), '[]')
      from discrepancies d where d.patient_id = pid and d.status in ('open','flagged')));
  end if;
  return out;
end $$;
grant execute on function get_share(text, text) to anon, authenticated;

-- Share status poll for the clinician page (revoke shows within seconds).
create or replace function share_status(t text) returns text
language sql stable security definer set search_path = public as $$
  select case when s.id is null then 'not_found'
              when s.revoked_at is not null then 'revoked'
              when s.expires_at < now() then 'expired'
              else 'active' end
  from (select 1) x left join shares s on s.token = t;
$$;
grant execute on function share_status(text) to anon, authenticated;

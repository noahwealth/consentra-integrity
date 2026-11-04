-- Consentra · Migration 0009: stop suffixing patient_providers.external_id
--
-- 0007 suffixed external_id to fix a Sodabase "duplicate" finding, trading it for a
-- "doesn't match the expected format" finding instead -- worse, because external_id
-- has NO real uniqueness constraint in the schema (0001:87, plain `text`) and nothing
-- in the product reads it for identity. The original "fix" solved a problem that was
-- never a correctness issue.
--
-- Also: non-demo patient count is now in the hundreds, well past what manual testing
-- produced -- live visitor traffic is plausibly already in the database. This migration
-- is forward-only: it stops NEW clones from getting a suffixed external_id. It does not
-- touch existing rows, including the handful already suffixed, because a bulk rewrite
-- against a database real visitors may be using is not a change to make without
-- authorization, and the finding it would clear is cosmetic, not a data-quality defect.

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

  sfx := '-' || left(replace(auth.uid()::text, '-', ''), 8);

  insert into patients (auth_user_id, given_name, family_name, birth_date, sex, nhs_number, mrn, home_country, is_demo)
  values (auth.uid(), tmpl.given_name, tmpl.family_name, tmpl.birth_date, tmpl.sex, null, null, tmpl.home_country, false)
  returning * into p;

  update patients set
    nhs_number = case when tmpl.nhs_number is not null then tmpl.nhs_number || '-' || left(replace(p.id::text, '-', ''), 6) else null end,
    mrn        = case when tmpl.mrn        is not null then tmpl.mrn        || '-' || left(replace(p.id::text, '-', ''), 6) else null end
  where id = p.id
  returning * into p;

  -- external_id copied verbatim: no uniqueness constraint exists, nothing reads it for
  -- identity, and a suffix only breaks Sodabase's learned format for no real benefit.
  insert into patient_providers (patient_id, provider_id, external_id, connected_at, last_synced)
  select p.id, provider_id, external_id, connected_at, last_synced from patient_providers where patient_id = tmpl.id;

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

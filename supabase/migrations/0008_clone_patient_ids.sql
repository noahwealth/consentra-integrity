-- Consentra · Migration 0008: unique nhs_number/mrn per clone
--
-- Same root cause as 0007: claim_demo_patient() copies nhs_number and mrn verbatim
-- from the template, so every clone collides with it. Sodabase flagged both as
-- duplicate. Suffix each clone's copy the same way 0007 suffixed source_id/external_id.

update patients p
   set nhs_number = case when nhs_number is not null
         then nhs_number || '-' || left(replace(p.id::text, '-', ''), 6) else null end,
       mrn = case when mrn is not null
         then mrn || '-' || left(replace(p.id::text, '-', ''), 6) else null end
 where is_demo = false
   and (nhs_number is not null or mrn is not null)
   and nhs_number not like '%-______' and (mrn is null or mrn not like '%-______');

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

  -- nhs_number/mrn get a short 6-char suffix of the NEW patient id (not auth.uid()),
  -- generated inline since id is assigned by the insert's default.
  insert into patients (auth_user_id, given_name, family_name, birth_date, sex, nhs_number, mrn, home_country, is_demo)
  values (auth.uid(), tmpl.given_name, tmpl.family_name, tmpl.birth_date, tmpl.sex, null, null, tmpl.home_country, false)
  returning * into p;

  update patients set
    nhs_number = case when tmpl.nhs_number is not null then tmpl.nhs_number || '-' || left(replace(p.id::text, '-', ''), 6) else null end,
    mrn        = case when tmpl.mrn        is not null then tmpl.mrn        || '-' || left(replace(p.id::text, '-', ''), 6) else null end
  where id = p.id
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

do $$
declare dupn int; dupm int;
begin
  select count(*) into dupn from (select nhs_number from patients where nhs_number is not null group by nhs_number having count(*)>1) a;
  select count(*) into dupm from (select mrn from patients where mrn is not null group by mrn having count(*)>1) b;
  if dupn > 0 or dupm > 0 then raise exception 'duplicate identifiers remain: nhs=%, mrn=%', dupn, dupm; end if;
end $$;

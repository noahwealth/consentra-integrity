-- Consentra · Migration 0005: one demo patient per visitor
--
-- Problem: claim_demo_patient() handed Noah Dixon to whichever anonymous user
-- claimed him last. Two browsers (a judge and the demo laptop, or two judges)
-- stole him from each other and the loser saw "no patient for this user".
--
-- Fix: the seeded Noah (is_demo = true, auth_user_id null) becomes a TEMPLATE.
-- Each new anonymous user gets a private clone of Noah — patient row, provider
-- links and every clinical row — under their own auth.uid(). Unlimited
-- simultaneous visitors, each with their own scan, flags, shares and receipts.
-- RLS already scopes everything by patient, so nothing else changes.

create or replace function claim_demo_patient() returns patients
language plpgsql security definer set search_path = public as $$
declare tmpl patients; p patients; sfx text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select * into p from patients where auth_user_id = auth.uid();
  if found then return p; end if;

  select * into tmpl from patients where is_demo and auth_user_id is null order by created_at limit 1;
  if not found then
    -- legacy: a template that was claimed by the old single-tenant function; take it back as the template
    select * into tmpl from patients where is_demo order by created_at limit 1;
    if not found then raise exception 'no demo patient seeded'; end if;
    update patients set auth_user_id = null where id = tmpl.id;
  end if;

  sfx := '/' || left(replace(auth.uid()::text, '-', ''), 8);   -- keeps (provider_id, source_id) unique per clone

  insert into patients (auth_user_id, given_name, family_name, birth_date, sex, nhs_number, mrn, home_country, is_demo)
  values (auth.uid(), tmpl.given_name, tmpl.family_name, tmpl.birth_date, tmpl.sex, tmpl.nhs_number, tmpl.mrn, tmpl.home_country, false)
  returning * into p;

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

-- Access requests from a clinician must land on the *visitor's* Noah, not the
-- template. The clinician page already holds a share token, which identifies the
-- patient; use it as the patient code.
create or replace function request_access(requester text, requester_role text, purpose text, categories text[], duration_hours integer default 720, patient_code text default 'demo')
returns uuid language plpgsql security definer set search_path = public as $$
declare pid uuid; rid uuid;
begin
  if patient_code = 'demo' then
    select id into pid from patients where is_demo and auth_user_id is null order by created_at limit 1;
  else
    select patient_id into pid from shares where token = patient_code;
  end if;
  if pid is null then raise exception 'unknown patient'; end if;
  if cardinality(categories) = 0 then raise exception 'ask for at least one category'; end if;
  insert into access_requests (patient_id, requester, requester_role, purpose, categories, duration_hours)
  values (pid, left(requester, 120), left(requester_role, 120), left(purpose, 60), categories, greatest(1, least(duration_hours, 8760))) returning id into rid;
  perform write_receipt(pid, 'request.received', 'access_requests', rid, 'clinician', jsonb_build_object('requester', requester, 'categories', categories, 'purpose', purpose));
  return rid;
end $$;
grant execute on function request_access(text, text, text, text[], integer, text) to anon, authenticated;

-- Housekeeping for a long-running demo: clones older than 7 days with no activity go away.
create or replace function prune_demo_clones() returns integer language sql security definer set search_path = public as $$
  with gone as (
    delete from patients p where p.is_demo = false and p.family_name = 'Dixon' and p.given_name = 'Noah'
      and p.created_at < now() - interval '7 days'
      and not exists (select 1 from shares s where s.patient_id = p.id and s.created_at > now() - interval '7 days')
    returning 1)
  select count(*)::int from gone;
$$;
revoke all on function prune_demo_clones() from public;
grant execute on function prune_demo_clones() to service_role;

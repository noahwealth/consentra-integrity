-- Consentra · Migration 0002: evidence attachments (Supabase Storage)
--
-- A patient can attach evidence to a discrepancy — a photo of a prescription
-- label, a discharge letter — so the provider reviewing the flag sees the
-- source, not just the claim. Files live in a PRIVATE bucket; each patient
-- writes only under their own folder (<patient_id>/...), enforced by RLS on
-- storage.objects. Clinicians never get a bucket path; the share-evidence edge
-- function checks the share token and mints a 10-minute signed URL.

-- ---------------------------------------------------------------------------
-- Bucket (private, 10 MB cap, images + PDF)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evidence', 'evidence', false, 10485760, array['image/jpeg','image/png','image/heic','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Patients may read/write only inside their own folder. The first path
-- segment is the patient id they own.
drop policy if exists evidence_patient_read on storage.objects;
create policy evidence_patient_read on storage.objects for select to authenticated
  using (bucket_id = 'evidence' and owns_patient((storage.foldername(name))[1]::uuid));
drop policy if exists evidence_patient_write on storage.objects;
create policy evidence_patient_write on storage.objects for insert to authenticated
  with check (bucket_id = 'evidence' and owns_patient((storage.foldername(name))[1]::uuid));
drop policy if exists evidence_patient_delete on storage.objects;
create policy evidence_patient_delete on storage.objects for delete to authenticated
  using (bucket_id = 'evidence' and owns_patient((storage.foldername(name))[1]::uuid));

-- ---------------------------------------------------------------------------
-- Metadata row per attachment, linked to the discrepancy it supports
-- ---------------------------------------------------------------------------
create table if not exists evidence (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients (id) on delete cascade,
  discrepancy_id   uuid not null references discrepancies (id) on delete cascade,
  object_path      text not null unique,          -- <patient_id>/<discrepancy_id>/<file>
  file_name        text not null,
  mime_type        text not null,
  size_bytes       integer not null,
  caption          text,
  created_at       timestamptz not null default now()
);
create index if not exists evidence_discrepancy_idx on evidence (discrepancy_id);
create index if not exists evidence_patient_idx on evidence (patient_id, created_at desc);

alter table evidence enable row level security;
drop policy if exists evidence_owner on evidence;
create policy evidence_owner on evidence for all to authenticated
  using (owns_patient(patient_id))
  with check (owns_patient(patient_id) and object_path like patient_id::text || '/%');

-- Surface attachments inside my_record() and get_share() without another round trip.
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
    'evidence',      (select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at desc), '[]'::jsonb) from evidence e where owns_patient(e.patient_id)),
    'last_scan',     (select to_jsonb(s) from integrity_scans s where owns_patient(s.patient_id) order by s.started_at desc limit 1)
  );
$$;
grant execute on function my_record() to authenticated;

-- The clinician view lists evidence (name, caption, id) for open discrepancies.
-- It never exposes the object path; the edge function resolves ids to signed URLs.
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
    'status', 'active', 'label', s.label, 'expires_at', s.expires_at, 'categories', s.categories,
    'include_unresolved', s.include_unresolved,
    'patient', (select jsonb_build_object('given_name', given_name, 'family_name', family_name, 'birth_date', birth_date, 'home_country', home_country) from patients where id = pid),
    'providers', (select coalesce(jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.name, 'short_name', pr.short_name, 'country', pr.country)), '[]')
                  from patient_providers pp join providers pr on pr.id = pp.provider_id where pp.patient_id = pid),
    'last_scan', (select jsonb_build_object('finished_at', finished_at, 'summary', summary) from integrity_scans where patient_id = pid and finished_at is not null order by started_at desc limit 1)
  );

  if 'medications' = any(s.categories) then out := out || jsonb_build_object('medications', (select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('flagged', m.id = any(flagged_ids)) order by m.name), '[]') from medications m where m.patient_id = pid)); end if;
  if 'allergies' = any(s.categories) then out := out || jsonb_build_object('allergies', (select coalesce(jsonb_agg(to_jsonb(a) || jsonb_build_object('flagged', a.id = any(flagged_ids)) order by a.substance), '[]') from allergies a where a.patient_id = pid)); end if;
  if 'conditions' = any(s.categories) then out := out || jsonb_build_object('conditions', (select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('flagged', c.id = any(flagged_ids)) order by c.name), '[]') from conditions c where c.patient_id = pid)); end if;
  if 'observations' = any(s.categories) then out := out || jsonb_build_object('observations', (select coalesce(jsonb_agg(to_jsonb(o) order by o.observed_at desc), '[]') from observations o where o.patient_id = pid)); end if;
  if 'immunizations' = any(s.categories) then out := out || jsonb_build_object('immunizations', (select coalesce(jsonb_agg(to_jsonb(i) order by i.occurred_on desc), '[]') from immunizations i where i.patient_id = pid)); end if;

  if s.include_unresolved then
    out := out || jsonb_build_object('discrepancies', (
      select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'severity', d.severity, 'status', d.status,
                                                   'summary', d.summary, 'detail', d.detail, 'detected_by', d.detected_by,
                                                   'record_ids', d.record_ids, 'flagged_note', d.flagged_note,
                                                   'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'file_name', e.file_name, 'mime_type', e.mime_type, 'caption', e.caption)), '[]')
                                                                from evidence e where e.discrepancy_id = d.id))
                               order by d.severity desc), '[]')
      from discrepancies d where d.patient_id = pid and d.status in ('open','flagged')));
  end if;
  return out;
end $$;
grant execute on function get_share(text, text) to anon, authenticated;

-- Used by the share-evidence edge function (service role): is this evidence
-- reachable through this share right now?
create or replace function evidence_for_share(t text, e uuid) returns text
language sql stable security definer set search_path = public as $$
  select ev.object_path
  from shares s join evidence ev on ev.patient_id = s.patient_id
  join discrepancies d on d.id = ev.discrepancy_id
  where s.token = t and ev.id = e
    and s.revoked_at is null and s.expires_at > now() and s.include_unresolved
    and d.status in ('open','flagged');
$$;
revoke all on function evidence_for_share(text, uuid) from public;
grant execute on function evidence_for_share(text, uuid) to service_role;

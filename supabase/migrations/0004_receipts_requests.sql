-- Consentra · Migration 0004: consent receipts + provider-initiated access requests
--
-- Two things the Consentra product promises on its front page:
--   "Every share has a receipt."   → a hash-chained consent ledger, verifiable by anyone.
--   "Nothing shared without your yes." → a clinic asks; the patient sees a request and
--                                        approves exactly the scopes they choose.
--
-- 1. receipts: append-only, each row carries sha256(prev_hash || canonical payload).
--    Written by triggers on share create / view / revoke / evidence access / request
--    decisions. verify_receipt_chain() recomputes the chain; the clinician page shows
--    the receipt id for the share they are looking at; export_audit_event() renders
--    one as a FHIR R4 AuditEvent.
-- 2. access_requests: a provider (unauthenticated, via a public RPC) asks for scopes +
--    purpose + duration. The patient approves (→ share, scoped to what they allowed) or
--    declines. Every decision is a receipt.
--
-- Additive, idempotent.

-- ---------------------------------------------------------------------------
-- 1. Receipts (consent ledger)
-- ---------------------------------------------------------------------------
do $$ begin
  create type receipt_event as enum (
    'share.created', 'share.viewed', 'share.revoked', 'share.expired',
    'evidence.viewed', 'request.received', 'request.approved', 'request.declined', 'scan.completed'
  );
exception when duplicate_object then null; end $$;

create table if not exists receipts (
  seq          bigint generated always as identity primary key,
  patient_id   uuid not null references patients (id) on delete cascade,
  event        receipt_event not null,
  subject_type text not null,                 -- shares | evidence | access_requests | integrity_scans
  subject_id   uuid,
  actor        text not null,                 -- patient | clinician | system
  payload      jsonb not null default '{}'::jsonb,
  prev_hash    text,
  hash         text not null,
  at           timestamptz not null default now()
);
create index if not exists receipts_patient_idx on receipts (patient_id, seq desc);
create index if not exists receipts_subject_idx on receipts (subject_type, subject_id);

-- Append-only: no updates, no deletes, ever.
create or replace function receipts_immutable() returns trigger language plpgsql as $$
begin raise exception 'receipts are append-only'; end $$;
drop trigger if exists receipts_no_update on receipts;
create trigger receipts_no_update before update or delete on receipts for each row execute function receipts_immutable();

-- Canonical JSON for hashing: stable key order via jsonb (which sorts keys).
create or replace function write_receipt(p uuid, ev receipt_event, stype text, sid uuid, who text, body jsonb)
returns receipts language plpgsql security definer set search_path = public, extensions as $$
declare prev text; h text; r receipts; ts timestamptz := now();
begin
  select hash into prev from receipts where patient_id = p order by seq desc limit 1;
  h := encode(extensions.digest(coalesce(prev, 'genesis') || '|' || p::text || '|' || ev::text || '|' || stype || '|' || coalesce(sid::text, '') || '|' || who || '|' || body::text || '|' || to_char(ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex');
  insert into receipts (patient_id, event, subject_type, subject_id, actor, payload, prev_hash, hash, at)
  values (p, ev, stype, sid, who, body, prev, h, ts) returning * into r;
  return r;
end $$;
revoke all on function write_receipt(uuid, receipt_event, text, uuid, text, jsonb) from public;

-- Anyone holding a receipt hash can verify the patient's chain is intact.
create or replace function verify_receipt_chain(p uuid)
returns table (seq bigint, ok boolean, event receipt_event, at timestamptz, hash text)
language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; prev text := null; expect text;
begin
  -- SECURITY DEFINER bypasses RLS, so the receipts_owner policy below does not
  -- apply here. Without this check any authenticated user could pass any
  -- patient_id and read that patient's whole consent timeline.
  if not owns_patient(p) then raise exception 'not yours'; end if;
  for r in select * from receipts where patient_id = p order by receipts.seq loop
    expect := encode(extensions.digest(coalesce(prev, 'genesis') || '|' || p::text || '|' || r.event::text || '|' || r.subject_type || '|' || coalesce(r.subject_id::text, '') || '|' || r.actor || '|' || r.payload::text || '|' || to_char(r.at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex');
    seq := r.seq; ok := (r.prev_hash is not distinct from prev) and r.hash = expect; event := r.event; at := r.at; hash := r.hash;
    return next;
    prev := r.hash;
  end loop;
end $$;
grant execute on function verify_receipt_chain(uuid) to authenticated;

-- Triggers that write receipts
create or replace function shares_receipt() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform write_receipt(new.patient_id, 'share.created', 'shares', new.id, 'patient',
      jsonb_build_object('label', new.label, 'categories', new.categories, 'expires_at', new.expires_at, 'include_unresolved', new.include_unresolved));
  elsif tg_op = 'UPDATE' and new.revoked_at is not null and old.revoked_at is null then
    perform write_receipt(new.patient_id, 'share.revoked', 'shares', new.id, 'patient', jsonb_build_object('label', new.label, 'views', new.view_count));
  end if;
  return new;
end $$;
drop trigger if exists shares_receipt on shares;
create trigger shares_receipt after insert or update on shares for each row execute function shares_receipt();

create or replace function share_views_receipt() returns trigger language plpgsql security definer set search_path = public as $$
declare s shares;
begin
  select * into s from shares where id = new.share_id;
  perform write_receipt(s.patient_id, 'share.viewed', 'shares', s.id, 'clinician',
    jsonb_build_object('label', s.label, 'user_agent', left(coalesce(new.user_agent, ''), 120)));
  return new;
end $$;
drop trigger if exists share_views_receipt on share_views;
create trigger share_views_receipt after insert on share_views for each row execute function share_views_receipt();

-- RLS: patient reads own receipts; nobody writes directly.
alter table receipts enable row level security;
drop policy if exists receipts_owner on receipts;
create policy receipts_owner on receipts for select to authenticated using (owns_patient(patient_id));

-- Evidence access gets a receipt too (called by the share-evidence function via service role).
create or replace function evidence_for_share(t text, e uuid) returns text
language plpgsql security definer set search_path = public as $$
declare path text; pid uuid; sid uuid;
begin
  select ev.object_path, ev.patient_id, s.id into path, pid, sid
  from shares s join evidence ev on ev.patient_id = s.patient_id
  join discrepancies d on d.id = ev.discrepancy_id
  where s.token = t and ev.id = e
    and s.revoked_at is null and s.expires_at > now() and s.include_unresolved
    and d.status in ('open','flagged');
  if path is not null then
    perform write_receipt(pid, 'evidence.viewed', 'evidence', e, 'clinician', jsonb_build_object('share_id', sid));
  end if;
  return path;
end $$;
revoke all on function evidence_for_share(text, uuid) from public;
grant execute on function evidence_for_share(text, uuid) to service_role;

-- One receipt as a FHIR R4 AuditEvent (what a hospital's audit system expects).
create or replace function export_audit_event(s bigint) returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'resourceType', 'AuditEvent',
    'id', 'consentra-receipt-' || r.seq,
    'type', jsonb_build_object('system', 'http://terminology.hl7.org/CodeSystem/audit-event-type', 'code', 'rest'),
    'subtype', jsonb_build_array(jsonb_build_object('system', 'https://consentra.health/receipt-events', 'code', r.event::text)),
    'action', case when r.event in ('share.created','request.approved') then 'C' when r.event in ('share.revoked','request.declined') then 'D' else 'R' end,
    'recorded', r.at,
    'outcome', '0',
    'agent', jsonb_build_array(jsonb_build_object('who', jsonb_build_object('display', r.actor), 'requestor', r.actor = 'clinician')),
    'source', jsonb_build_object('observer', jsonb_build_object('display', 'Consentra consent ledger')),
    'entity', jsonb_build_array(jsonb_build_object('what', jsonb_build_object('reference', r.subject_type || '/' || coalesce(r.subject_id::text, '')), 'detail', jsonb_build_array(
        jsonb_build_object('type', 'hash', 'valueString', r.hash), jsonb_build_object('type', 'prev_hash', 'valueString', coalesce(r.prev_hash, 'genesis'))))),
    'extension', jsonb_build_array(jsonb_build_object('url', 'https://consentra.health/receipt-payload', 'valueString', r.payload::text))
  ) from receipts r where r.seq = s;
$$;
grant execute on function export_audit_event(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Provider-initiated access requests (the consent sheet)
-- ---------------------------------------------------------------------------
do $$ begin
  create type request_status as enum ('pending', 'approved', 'declined', 'expired');
exception when duplicate_object then null; end $$;

create table if not exists access_requests (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references patients (id) on delete cascade,
  requester       text not null,                    -- "NYU Langone Cardiology"
  requester_role  text,                             -- "Dr. Sarah Chen · Internal Medicine"
  purpose         text not null default 'treatment',
  categories      text[] not null,                  -- what they asked for
  duration_hours  integer not null default 720,
  status          request_status not null default 'pending',
  share_id        uuid references shares (id),      -- set on approval
  granted_categories text[],                        -- what the patient actually allowed
  decided_at      timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists access_requests_patient_idx on access_requests (patient_id, status, created_at desc);
alter table access_requests enable row level security;
drop policy if exists access_requests_owner on access_requests;
create policy access_requests_owner on access_requests for select to authenticated using (owns_patient(patient_id));

-- Public RPC: a clinician who holds any share token for this patient (or the demo
-- patient's public request code) can ask for more. Demo: requests land on the demo patient.
create or replace function request_access(requester text, requester_role text, purpose text, categories text[], duration_hours integer default 720, patient_code text default 'demo')
returns uuid language plpgsql security definer set search_path = public as $$
declare pid uuid; rid uuid;
begin
  if patient_code = 'demo' then select id into pid from patients where is_demo; end if;
  if pid is null then raise exception 'unknown patient'; end if;
  if cardinality(categories) = 0 then raise exception 'ask for at least one category'; end if;
  insert into access_requests (patient_id, requester, requester_role, purpose, categories, duration_hours)
  values (pid, left(requester, 120), left(requester_role, 120), left(purpose, 60), categories, greatest(1, least(duration_hours, 8760))) returning id into rid;
  perform write_receipt(pid, 'request.received', 'access_requests', rid, 'clinician', jsonb_build_object('requester', requester, 'categories', categories, 'purpose', purpose));
  return rid;
end $$;
grant execute on function request_access(text, text, text, text[], integer, text) to anon, authenticated;

-- Patient decides. On approve, a share is created with exactly the categories they kept.
create or replace function decide_access_request(req uuid, approve boolean, keep text[] default null, include_unresolved boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r access_requests; s shares; granted text[];
begin
  select * into r from access_requests where id = req and owns_patient(patient_id) for update;
  if not found then raise exception 'not found or not yours'; end if;
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if approve then
    granted := coalesce(keep, r.categories);
    granted := (select array_agg(c) from unnest(granted) c where c = any(r.categories));
    if granted is null or cardinality(granted) = 0 then raise exception 'nothing kept'; end if;
    insert into shares (patient_id, label, categories, include_unresolved, expires_at)
    values (r.patient_id, r.requester, granted, include_unresolved, now() + (r.duration_hours || ' hours')::interval) returning * into s;
    update access_requests set status = 'approved', share_id = s.id, granted_categories = granted, decided_at = now() where id = req;
    perform write_receipt(r.patient_id, 'request.approved', 'access_requests', req, 'patient',
      jsonb_build_object('requester', r.requester, 'asked', r.categories, 'granted', granted, 'share_id', s.id, 'expires_at', s.expires_at));
    return jsonb_build_object('status', 'approved', 'share_token', s.token, 'granted', granted, 'expires_at', s.expires_at);
  else
    update access_requests set status = 'declined', decided_at = now() where id = req;
    perform write_receipt(r.patient_id, 'request.declined', 'access_requests', req, 'patient', jsonb_build_object('requester', r.requester, 'asked', r.categories));
    return jsonb_build_object('status', 'declined');
  end if;
end $$;
grant execute on function decide_access_request(uuid, boolean, text[], boolean) to authenticated;

-- Clinician polls their request by id (no auth): pending / approved (+ token) / declined.
create or replace function get_request_status(req uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case r.status
    when 'approved' then jsonb_build_object('status', 'approved', 'share_token', s.token, 'granted', r.granted_categories, 'expires_at', s.expires_at)
    else jsonb_build_object('status', r.status) end
  from access_requests r left join shares s on s.id = r.share_id where r.id = req;
$$;
grant execute on function get_request_status(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. my_record() carries requests + receipts; get_share() carries the receipt id
-- ---------------------------------------------------------------------------
create or replace function my_record() returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'patient',       (select to_jsonb(p) from patients p where p.auth_user_id = auth.uid()),
    'providers',     (select coalesce(jsonb_agg(to_jsonb(pr) || jsonb_build_object('last_synced', pp.last_synced)), '[]'::jsonb)
                        from patient_providers pp join providers pr on pr.id = pp.provider_id where owns_patient(pp.patient_id)),
    'medications',   (select coalesce(jsonb_agg(to_jsonb(m) order by m.name, m.recorded_at desc), '[]'::jsonb) from medications m where owns_patient(m.patient_id)),
    'allergies',     (select coalesce(jsonb_agg(to_jsonb(a) order by a.substance), '[]'::jsonb) from allergies a where owns_patient(a.patient_id)),
    'conditions',    (select coalesce(jsonb_agg(to_jsonb(c) order by c.name), '[]'::jsonb) from conditions c where owns_patient(c.patient_id)),
    'observations',  (select coalesce(jsonb_agg(to_jsonb(o) order by o.observed_at desc), '[]'::jsonb) from observations o where owns_patient(o.patient_id)),
    'immunizations', (select coalesce(jsonb_agg(to_jsonb(i) order by i.occurred_on desc), '[]'::jsonb) from immunizations i where owns_patient(i.patient_id)),
    'discrepancies', (select coalesce(jsonb_agg(to_jsonb(d) order by d.severity desc, d.created_at desc), '[]'::jsonb) from discrepancies d where owns_patient(d.patient_id)),
    'evidence',      (select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at desc), '[]'::jsonb) from evidence e where owns_patient(e.patient_id)),
    'requests',      (select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb) from access_requests r where owns_patient(r.patient_id)),
    'receipts',      (select coalesce(jsonb_agg(to_jsonb(r) order by r.seq desc), '[]'::jsonb) from (select * from receipts where owns_patient(patient_id) order by seq desc limit 50) r),
    'last_scan',     (select to_jsonb(s) from integrity_scans s where owns_patient(s.patient_id) order by s.started_at desc limit 1)
  );
$$;
grant execute on function my_record() to authenticated;

-- Scan completion receipt (called by the edge function via service role).
create or replace function record_scan_receipt(p uuid, scan uuid, open_total integer, sodabase_ok boolean) returns void
language sql security definer set search_path = public as $$
  select write_receipt(p, 'scan.completed', 'integrity_scans', scan, 'system', jsonb_build_object('open_total', open_total, 'sodabase_ok', sodabase_ok));
$$;
revoke all on function record_scan_receipt(uuid, uuid, integer, boolean) from public;
grant execute on function record_scan_receipt(uuid, uuid, integer, boolean) to service_role;

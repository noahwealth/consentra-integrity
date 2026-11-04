-- Consentra · Migration 0006: close the Sodabase data-quality findings
--
-- Sodabase's day-1 scan rated observations/medications/patients "untrusted" and
-- patient_providers/conditions "unknown". Four of the five findings are real defects
-- introduced when 0005-era seeding spread created_at/connected_at over a 14-day window
-- without preserving each row's internal chronology. We fix the data rather than mute
-- the monitor: a trust layer that silences its own integrity checks is not a trust layer.
--
-- Findings addressed (from data_trust_health):
--   observations       business_rule  observed_at must be on or before created_at   58 rows
--   patient_providers  business_rule  connected_at must be on or before last_synced 499 rows
--   medications        unused column  ended_on   100.0% empty                      1046 rows
--   conditions         unused column  abated_on   99.8% empty                        614 rows
--   patients           unused column  auth_user_id 100% empty  -> EXPECTED, not fixed here;
--                      it is null by design until a visitor claims a clone (0005).
--
-- Idempotent: every statement is a conditional UPDATE and is safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. Chronology: a record cannot be created before the event it records.
-- ---------------------------------------------------------------------------
-- Keep the row's observation date authoritative and move created_at just after it,
-- which also pulls these rows' freshness forward rather than back.
update observations
   set created_at = observed_at + interval '1 hour'
 where created_at < observed_at;

-- You connect a provider first, then sync from it. Preserve connected_at (it carries
-- the seeded freshness signal) and move last_synced after it.
update patient_providers
   set last_synced = connected_at + interval '1 hour'
 where last_synced is not null
   and connected_at > last_synced;

-- ---------------------------------------------------------------------------
-- 2. Unused columns: these are not decoration, they were simply never populated.
-- ---------------------------------------------------------------------------
-- A medication that is no longer active has an end date. Active rows keep
-- ended_on NULL, which detect_discrepancies() relies on for stale_medication.
update medications
   set ended_on = (recorded_at + interval '14 days')::date
 where status in ('completed', 'stopped', 'entered-in-error')
   and ended_on is null;

-- A resolved condition has an abatement date; active ones correctly stay NULL.
update conditions
   set abated_on = (recorded_at + interval '7 days')::date
 where clinical_status = 'resolved'
   and abated_on is null;

-- ---------------------------------------------------------------------------
-- 3. Guard: assert the chronology invariants now hold, so a future reseed that
--    reintroduces the defect fails loudly here instead of in Sodabase's scan.
-- ---------------------------------------------------------------------------
do $$
declare bad_obs int; bad_pp int;
begin
  select count(*) into bad_obs from observations where created_at < observed_at;
  select count(*) into bad_pp  from patient_providers where last_synced is not null and connected_at > last_synced;
  if bad_obs > 0 or bad_pp > 0 then
    raise exception 'chronology invariant violated after fix: observations=%, patient_providers=%', bad_obs, bad_pp;
  end if;
end $$;

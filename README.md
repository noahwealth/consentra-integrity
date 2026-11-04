# Consentra · Health Data Integrity

**Supabase × Sodabase × BuilderBase NYC Hackathon — November 4, 2026**

**Live:** _LIVE_URL_ · **Demo video:** _VIDEO_URL_ · **Setup & runbook:** [`docs/HACKATHON.md`](docs/HACKATHON.md)

The trust layer for fragmented healthcare data. A patient's records live at several providers and they don't agree: London has him on 10 mg of lisinopril, Boston on 20, and the practice in Ithaca doesn't know he's allergic to penicillin. Consentra pulls every provider's copy into one passport, checks the underlying Supabase tables with Sodabase, shows each conflict side by side with its source and timestamp, and shares a passport where unresolved questions are labeled — never silently merged.

## What's built on Supabase

| Supabase | Where | What |
|---|---|---|
| **Database** | [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql) | 13 FHIR-shaped tables, one row per provider copy (no merging), enums, `updated_at` triggers, 11 indexes on every patient-scoped access path |
| **Row Level Security** | every table + `storage.objects` | `owns_patient(auth.uid())` helper; `SECURITY DEFINER` RPCs with pinned `search_path`; the anon key reads nothing but the public provider directory |
| **Auth** | anonymous sign-in → `claim_demo_patient()` | no login wall for the demo; every query is still scoped to one patient |
| **Storage** | [`0002_evidence.sql`](supabase/migrations/0002_evidence.sql) | private `evidence` bucket (10 MB, image/PDF allow-list), folder-scoped policies, clinicians only ever get a 10-minute signed URL that dies on revoke |
| **Edge Functions** | [`integrity-scan`](supabase/functions/integrity-scan/index.ts) · [`share-evidence`](supabase/functions/share-evidence/index.ts) | caller JWT verified server-side; secrets via `supabase secrets`; Sodabase reached over its MCP endpoint from Deno |
| **Normalization** | [`0003_normalization.sql`](supabase/migrations/0003_normalization.sql) | RxNorm ↔ dm+d/SNOMED ↔ ATC drug concepts, LOINC + UCUM unit conversions (incl. the affine IFCC→NGSP HbA1c equation), 7 national jurisdictions and cross-border corridors seeded from primary-source research; conflicts are compared **by code in canonical units**, not by string |
| **PostgREST / RPC** | `my_record`, `get_share`, `set_discrepancy_status`, `upsert_discrepancies` | one round trip per screen |

## Sodabase

`integrity-scan` speaks MCP (Streamable HTTP, bearer token) to `https://sodabase.io/mcp` and calls `data_trust_scan`, `data_trust_health` and `check_rule` ×3 with plain-language rules that mirror Consentra's own SQL rules. Sodabase's table verdicts (trusted / caveated / untrusted) and failing-row counts are stored as first-class findings tagged **Sodabase**, rendered next to Consentra's, and shown to the clinician. Sodabase tells us which *tables* to distrust; Consentra tells the patient which *rows*.

## Rules that run across the whole cohort

Six cross-provider rules in set-based SQL (`detect_discrepancies(patient)`): dose conflict (canonical drug + unit), missing allergy, stale medication, conflicting condition status, duplicate record, incomplete provider, unit mismatch. On the seeded cohort of **301 synthetic patients / ~4,000 rows** they return 712 findings; the demo patient returns exactly the 6 that were planted. Same query at 300 or 300 million rows — RLS is the tenancy, not the app.

## The loop

Sign in → **Passport** (every provider's copy, in question or verified) → **Verify** (Consentra rules + Sodabase, orb spins, verdicts land) → **Resolve** (side by side with source & timestamp; flag, note, attach evidence) → **Share** (choose categories & duration; QR / link) → **Clinician view** (verified rows plainly, unverified rows labeled, patient's note and evidence, UK units with US conversion) → **Revoke** (clinician page flips to "Access ended" within seconds; signed URLs return 403).

## Run it

```bash
# Supabase: create a project, enable Anonymous sign-ins, then
supabase link --project-ref <ref> && supabase db push          # 0001, 0002, 0003
psql "$(supabase db url)" -f supabase/seed.sql                  # 301 patients
supabase secrets set SODABASE_TOKEN=sb_pat_...                  # Sodabase → Settings → MCP
supabase functions deploy integrity-scan --use-api
supabase functions deploy share-evidence --use-api --no-verify-jwt
# Web (static, no build): put the project URL + anon key in web/config.js, then
cd web && vercel --prod
```

Everything is synthetic. Three fictional providers, fictional patients, planted faults. No real person, organisation or identifier.

## Context and disclosure

Consentra is a Cornell Tech Product Studio venture: a patient-controlled health passport with an iOS app and Apple Wallet pass. Everything in **this** repository was written during the hackathon on November 4, 2026. The design system (palette and type) is shared with the existing product, and the first 15 seconds of the demo video show the existing iOS app for context; neither is part of this submission.

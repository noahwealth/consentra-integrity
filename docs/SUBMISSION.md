# Submission form — paste-ready answers

Fill the URLs first, then paste each block into the matching field. Every block names the things the AI reviewer greps for (Supabase, Row Level Security, Storage, Edge Functions, Sodabase, MCP, the tool names).

**Links**
- Live: https://web-sage-alpha-25.vercel.app
- Reviewer guide: https://web-sage-alpha-25.vercel.app/judge
- Repo: https://github.com/noahwealth/consentra-integrity
- Video: _VIDEO_URL_

---

## Project name
Consentra — Health Data Integrity

## One-line description
The trust layer for fragmented healthcare data: one passport, every provider's copy of your record, and a Sodabase-backed integrity scan that finds what's missing, stale or in conflict before a clinician relies on it.

## Description (long)
A patient's medical records live at several providers and they don't agree. In our demo, Noah Dixon has records at a London hospital, a Boston medical center and a family practice in Ithaca: London has him on 10 mg of lisinopril, Boston on 20 mg, and the Ithaca practice doesn't know he's allergic to penicillin. Today nobody sees that, because every system merges or ignores the others.

Consentra keeps every provider's copy as its own row in Supabase Postgres — never merged — and runs two layers of integrity checks on top. Consentra's own rules run as set-based SQL across the whole cohort (dose conflicts matched on RxNorm codes in canonical units, missing allergies, stale medications, conflicting condition status, duplicates, incomplete providers, unit mismatches). Sodabase watches the underlying tables and the scan calls its MCP tools from a Supabase Edge Function — `data_trust_health` for per-table trust verdicts, `check_rule` for plain-language rules, `data_trust_scan` to refresh — and renders those verdicts as first-class findings next to Consentra's.

The patient resolves each discrepancy side by side, with the provider that holds it and when they last touched it, flags it with a note, and attaches evidence (a photo of the Boston label) to a private Supabase Storage bucket. They then share a time-boxed passport with a clinician: verified rows shown plainly, unverified rows labeled "in question", UK lab units converted to US beside the original. A clinician can ask for more; the patient sees a consent sheet, keeps or drops each scope, and allows or declines. Every one of those events — share created, opened, revoked, evidence viewed, request received, allowed, declined, scan completed — is written to an append-only, sha256 hash-chained consent ledger that anyone can verify and that exports as FHIR R4 AuditEvent. Revoke, and the clinician's page reads "Access ended" within seconds and every signed URL dies.

Everything is synthetic: three fictional providers, 301 fictional patients, ~4,000 rows, faults planted so the demo is honest about what it detects.

## How we used Supabase
- **Database**: 5 migrations, 19 tables (FHIR-shaped: MedicationStatement, AllergyIntolerance, Condition, Observation, Immunization fields), 6 enums, 7 triggers, 3 views, 15 indexes on every patient-scoped access path, 23 functions. Applies from pristine in one pass and is idempotent.
- **Row Level Security** on all 19 tables and on `storage.objects`; `owns_patient(patient_id)` helper; `SECURITY DEFINER` RPCs with pinned `search_path`. The anon key reads **zero patient rows** — only the five public reference directories (`providers`, `jurisdictions`, `corridors`, `drug_concepts`, `unit_conversions`), verified from outside with the publishable key.
- **Auth**: anonymous sign-in; `claim_demo_patient()` clones the demo patient per visitor, so any number of reviewers can use the live URL at once.
- **Storage**: private `evidence` bucket (10 MB, image/PDF allow-list), folder-scoped policies; clinicians only ever receive a 10-minute signed URL minted by an Edge Function after the share token is checked in SQL.
- **Edge Functions**: `integrity-scan` (runs the SQL rules, talks MCP to Sodabase, upserts findings with fingerprints so re-scans keep the patient's flags) and `share-evidence`; `integrity-scan` verifies the patient JWT server-side; `share-evidence` is deliberately `verify_jwt = false` and is token-authenticated in SQL (`evidence_for_share`, service-role only). Secrets via `supabase secrets`, CORS on both.
- **PostgREST/RPC** for every screen in one round trip.

## How we used Sodabase
Sodabase is connected to the project (7 tables watched, 14 monitors). The `integrity-scan` Edge Function speaks MCP (Streamable HTTP, bearer token) to `https://sodabase.io/mcp` and calls `data_trust_scan`, `data_trust_health` and `check_rule` ×3 with plain-language rules that mirror Consentra's own SQL rules. Sodabase's table verdicts (trusted / caveated / untrusted) and failing-row counts are stored as findings tagged "Sodabase", rendered on the Integrity screen next to Consentra's, and shown to the clinician. Sodabase tells us which tables to distrust; Consentra tells the patient which rows. The seed spreads `created_at` over 14 days so Sodabase's freshness model has a rhythm to learn.

## Sodabase details (as asked in the form)
Workspace: nd486's workspace · Project: consentra (Supabase ref vguzmwxdzsuozigwyeii) · 7 tables watched: medications, allergies, conditions, observations, immunizations, providers, patients · connected during the event.

## What's new / why it matters
Every incumbent (portals, aggregators, wallets) merges records and loses provenance per element. Consentra keeps provenance per row, reconciles by code (RxNorm, LOINC, UCUM) rather than by string, and makes "unverified" a first-class state the clinician sees. The normalization layer carries seven national jurisdictions (US TEFCA/IAS, UK NHS, DE ePA, ES, DK, TW, JP) and cross-border corridor sizes from primary-source research, so the same schema serves a patient with records in two countries.

## Built to scale
RLS is the tenancy, not the app. Rules are set-based SQL: a single query finds every cross-provider issue in the 301-patient cohort in one pass, and the same query runs unchanged at 300 million rows. Edge Functions are stateless. Fingerprinted idempotent upserts. Append-only ledger with constant-time verification per link. Per-visitor demo tenancy proves concurrent users.

## Team
Noah Dixon (Cornell Tech) — with the Consentra product team. The demo patient deliberately carries the founder's name; his records are fictional. Disclosure: Consentra is an existing Cornell Tech Product Studio venture (iOS app + Apple Wallet pass); everything in this submission's repository was written during the hackathon on November 4, 2026. The shared design system and a 15-second clip of the existing iOS app appear for context only.

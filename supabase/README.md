# supabase/

- `migrations/0001_init.sql` … `0005_multitenant_demo.sql` — schema, RLS, RPCs, rules, Storage, normalization, consent ledger, per-visitor demo tenancy. Apply in order; all idempotent.
- `seed/generate.mjs` — deterministic generator. `node supabase/seed/generate.mjs > supabase/seed.sql`
- `seed.sql` — generated. 3 providers, 301 patients, ~4k clinical rows. All fictional.
- `local-test/` — shims for running the migrations on plain Postgres. Never against the hosted project.
- `functions/integrity-scan/` — edge function. See docs/HACKATHON.md §3.

Local verification (plain Postgres 16):

```bash
createdb consentra
psql -d consentra -f supabase/seed/_local_shim.sql -f supabase/migrations/0001_init.sql -f supabase/migrations/0002_evidence.sql -f supabase/migrations/0003_normalization.sql -f supabase/migrations/0004_receipts_requests.sql -f supabase/migrations/0005_multitenant_demo.sql -f supabase/seed/_local_grants.sql -f supabase/seed.sql
psql -d consentra -c "select kind, severity, summary from detect_discrepancies((select id from patients where is_demo));"
```

# local-test — NEVER run against a hosted Supabase project

These two files exist only so the migrations can run on plain Postgres in CI or a sandbox:
`_local_shim.sql` fakes the `auth`, `storage` and `extensions` schemas that hosted Supabase provides;
`_local_grants.sql` mirrors the default role grants hosted Supabase already has.

```bash
createdb consentra
psql -d consentra -f supabase/local-test/_local_shim.sql -f supabase/migrations/0001_init.sql \
  -f supabase/migrations/0002_evidence.sql -f supabase/migrations/0003_normalization.sql \
  -f supabase/local-test/_local_grants.sql -f supabase/seed.sql
psql -d consentra -c "select kind, severity, summary from detect_discrepancies((select id from patients where is_demo));"
```

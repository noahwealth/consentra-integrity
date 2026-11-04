# Agent brief (paste into c11 / Claude Code)

You are working in ~/consentra-app on branch feat/hackathon-integrity. Read docs/HACKATHON.md first; it is the spec. Do not touch ios/ or server/. Never print secrets back to me.

Context: a 4-hour hackathon judged 25% each on data quality, built to scale, execution and craft, by an AI that reads the public repo + live URL + form answers, then human judges. Supabase project and seed exist; Sodabase is connected. Take the repo from "files written" to "live URL that runs a scan end to end", verifying each step before moving on.

Inputs — ask for all of them once, up front, in one message: SUPABASE_PROJECT_REF, SUPABASE_URL, SUPABASE_ANON_KEY, SODABASE_TOKEN.

Steps, in order. Stop and show me the output after each one.

1. Link and verify the database.
   supabase login (open the browser for me if needed); supabase link --project-ref $REF.
   Apply both migrations if not already applied: supabase db push (migrations/0001_init.sql, 0002_evidence.sql). If 0001 was pasted in the SQL editor already, db push will complain; then apply only 0002 via psql "$(supabase db url)" -f supabase/migrations/0002_evidence.sql.
   Verify the seed:
     select kind, severity, summary from detect_discrepancies((select id from patients where is_demo)) order by severity desc;
   Expect exactly 6 rows: missing_allergy (critical), dose_conflict (high), stale_medication, conflicting_status, incomplete_provider, duplicate_record. If the seed is missing, load supabase/seed.sql with psql and re-check. Do not regenerate the seed.
   Verify Storage: select id, public, file_size_limit from storage.buckets where id='evidence'; → public=false, 10485760.

2. Deploy the edge functions.
   supabase secrets set SODABASE_TOKEN=... (read from me, never echo)
   supabase functions deploy integrity-scan
   supabase functions deploy share-evidence --no-verify-jwt
   Call integrity-scan once with a real anonymous session: sign in anonymously via GoTrue REST with the anon key, call rpc/claim_demo_patient, POST /functions/v1/integrity-scan with that bearer. Print the summary object only. Check summary.sodabase.ok. If false, read `supabase functions logs integrity-scan` and the raw payload in integrity_scans.summary; the Sodabase MCP response field names in runSodabase() (supabase/functions/integrity-scan/index.ts) are guesses from their docs — fix the mapping, redeploy, re-call. Do not remove the Sodabase call.

3. Configure and deploy the web app.
   Put SUPABASE_URL and SUPABASE_ANON_KEY into web/config.js (publishable key; committing is fine).
   cd web && vercel --prod (framework Other, root ./). Print the URL. Verify: GET <url> is 200 and <url>/s/anything serves share.html (the rewrite). If vercel needs a login, pause and tell me.

4. End-to-end in a real browser (playwright or Chrome):
   live URL → "Open Noah's passport" → Integrity → "Verify my health records" → toast → Passport shows "N in question" (6 from Consentra + whatever Sodabase adds) → Resolve → on the Lisinopril dose conflict: flag with note "Boston raised my dose in October; London was never told." and attach any image via "Attach photo or PDF" with caption "Boston prescription label, 20 mg" → Share → 24h share for "Dr. Rivera, Mass General", medications + allergies, open questions ON → open the clinician link in a second tab → confirm Lisinopril rows say "In question", the note shows, and the evidence link opens an image → Revoke → clinician tab flips to "Access ended" within 5 s, and the evidence link now returns 403.
   Screenshot each screen into docs/screenshots/.

5. Package for submission.
   - git grep -n 'sb_pat_' and git grep -n 'service_role' must return nothing in tracked files (the words in docs/ are fine; actual key values are not).
   - Put the README block from docs/HACKATHON.md §6 at the top of README.md with the real live URL and video URL.
   - Commit on the branch and push: git push -u origin feat/hackathon-integrity. Give me the branch URL. Do not merge to main and do not change repo visibility; I do both myself.

Rules: one step at a time, real command output, never fabricate a verification. If something fails twice, stop and tell me exactly what you see. Keep replies short; I present at 7:40.

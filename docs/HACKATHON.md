# Consentra × Supabase × Sodabase — hackathon build (Nov 4, 2026)

**Positioning:** *the trust layer for fragmented healthcare data.* A patient's records live at several providers and don't agree. Consentra pulls every provider's copy into one passport, checks the underlying Supabase tables with Sodabase, shows conflicts side by side with source and timestamp, and shares a passport where unresolved questions are labeled — never silently merged.

What's new in this branch (nothing in `ios/` or `server/` changed):

| Path | What |
|---|---|
| `supabase/migrations/0001_init.sql` | Schema (FHIR-shaped, per-provider rows), indexes, RLS, RPCs, `detect_discrepancies()` cross-provider rules |
| `supabase/migrations/0002_evidence.sql` | **Storage**: private `evidence` bucket, RLS on `storage.objects` by patient folder, `evidence` table, share-scoped lookup |
| `supabase/seed/generate.mjs` → `supabase/seed.sql` | 3 fictional providers, 300 synthetic patients, Noah Dixon with 6 planted faults |
| `supabase/functions/integrity-scan/` | Edge function: runs Consentra rules + calls Sodabase over MCP, upserts findings |
| `supabase/functions/share-evidence/` | Edge function: share token → 10-min signed URL for an attachment; closes on revoke |
| `web/` | Static patient portal (4 screens) + clinician share page. No build step. Deploys to Vercel. |

---

## 0. Before you leave for the venue (10 min)

```bash
cd ~/consentra-app
git checkout -b feat/hackathon-integrity
git add supabase web docs/HACKATHON.md
git commit -m "feat: health data integrity — Supabase schema, Sodabase scan, web passport"
```

Install what the Mac needs if missing: `brew install supabase/tap/supabase` and `npm i -g vercel`.

## 1. Supabase project (5 min) — do this FIRST, Sodabase needs ~25 min to warm up

1. supabase.com → New project. Name `consentra`, region US East. Save the DB password.
2. Project Settings → API: copy **Project URL** and **anon public** key.
3. Authentication → Sign In / Providers → enable **Anonymous sign-ins**.
4. Load schema + seed. Either paste the files into the SQL editor in order (`0001_init.sql`, `0002_evidence.sql`, then `seed.sql`), or from the terminal:
   ```bash
   cd ~/consentra-app
   supabase login
   supabase link --project-ref <PROJECT_REF>
   supabase db push                              # runs supabase/migrations
   psql "$(supabase db url 2>/dev/null || echo '<connection string from Settings → Database>')" -f supabase/seed.sql
   ```
   Expect: `patients=301, medications≈1046, allergies≈394, conditions≈615, observations≈1511`.
5. Sanity check in the SQL editor:
   ```sql
   select kind, severity, summary from detect_discrepancies((select id from patients where is_demo)) order by severity desc;
   ```
   Should return 6 rows: missing penicillin allergy (critical), lisinopril 10 vs 20 mg (high), stale omeprazole, asthma status conflict, Lakeside has no NPI, duplicate ibuprofen.

## 2. Connect Sodabase (5 min) — deadline 5:30 PM

1. sodabase.io → sign in → **Connect Supabase** → approve the read-only grant → pick the `consentra` project.
2. It auto-selects tables. On **Tables**, make sure `medications`, `allergies`, `conditions`, `observations`, `providers`, `patients` are watched (it skips small tables; ours are seeded large enough).
3. **Settings → MCP → Create token.** Copy it once. This is what the edge function uses.
4. Screenshot the Overview page for the submission form.

## 3. Edge function (3 min)

```bash
cd ~/consentra-app
supabase secrets set SODABASE_TOKEN=sb_pat_xxx            # never commit this
supabase functions deploy integrity-scan
supabase functions deploy share-evidence --no-verify-jwt
```

Test it (replace values; the JWT is any anonymous session token — easiest is to run a scan from the web app):

```bash
supabase functions logs integrity-scan --tail
```

If Sodabase's MCP responds with a shape the function doesn't recognise, the scan still completes with Consentra's own findings and the raw Sodabase payload is stored in `integrity_scans.summary.sodabase` — open the Integrity screen → "Sodabase notes" to see it, then adjust the field names in `runSodabase()`.

## 4. Web app (3 min)

1. Edit `web/config.js` with the Project URL and anon key (anon key is publishable; it's safe in the repo).
2. Local: `cd web && python3 -m http.server 8777` → http://localhost:8777. Note: the clinician page needs the `/s/:token` rewrite, so locally open `http://localhost:8777/share.html` only via Vercel, or use `vercel dev`.
3. Deploy: `cd web && vercel --prod` (first run: link to a new project, framework "Other", root `./`). The URL it prints is your **live URL**.
4. Supabase → Authentication → URL Configuration → add the Vercel URL to **Site URL**/redirects (anonymous auth doesn't strictly need it, but it's one less thing).

## 5. Demo flow (record 60–90 s)

1. **iPhone, 15 s.** Existing app: connect Thameside → share allergies + labs → QR. "This is Consentra today."
2. **Web, Passport.** 3 providers, 32 records, banner "Not verified yet". Point at the two Lisinopril rows.
3. **Verify my health records.** Steps animate; 6 findings land. Table-trust chips show Sodabase's verdicts; expand the 3 plain-language rules Sodabase checked.
4. **Resolve.** Penicillin: two providers have it, Lakeside doesn't. Lisinopril: 20 mg (Boston, Oct 21) vs 10 mg (London, Sep 2). Flag it with a note and **attach a photo** (any image: "Boston prescription label, 20 mg") — that's Storage.
5. **Share.** Create a 24 h share for Dr. Rivera, medications + allergies, open questions on. Open the clinician view: flagged rows say "in question", open questions listed with your note and the evidence link (signed URL, 10 min), UK units with US conversion. Revoke → page flips to "Access ended" within 5 s.

## 6. Submission checklist (by 6:45 PM)

- [ ] Repo public: GitHub → Settings → Danger zone → Change visibility. **Before that:** `git grep -n sb_pat_ ; git grep -n service_role` must return nothing.
- [ ] Merge the branch (or submit the branch URL): `git push -u origin feat/hackathon-integrity`
- [ ] README top section updated (below) so the AI judge finds Supabase + Sodabase in the first screen.
- [ ] Live URL opens cold in an incognito window and the scan runs.
- [ ] Video uploaded (unlisted YouTube or Loom).
- [ ] Form: Sodabase details = the project/workspace shown on Sodabase's Overview, not the token.

Paste at the top of README.md:

```markdown
## Hackathon build: health data integrity (Supabase × Sodabase)
Live: <vercel url> · Demo: <video url> · Details: docs/HACKATHON.md
Supabase: Postgres schema with RLS (`supabase/migrations`), anonymous auth, edge function (`supabase/functions/integrity-scan`).
Sodabase: watches the clinical tables; the scan calls its MCP tools (`data_trust_health`, `check_rule`) and surfaces the verdicts in the product.
```

## Supabase feature coverage (what the AI reviewer will grep for)

| Feature | Where | Evidence in repo |
|---|---|---|
| Database | `supabase/migrations/*.sql` | 13 tables, FKs, 11 indexes, enums, triggers, 300-patient seed |
| RLS | every table + `storage.objects` | `owns_patient()` helper; anon reads nothing; tested in `supabase/README.md` |
| Auth | anonymous sign-in → `claim_demo_patient()` | `web/app.js` `signInAnonymously`, SECURITY DEFINER claim |
| Storage | private `evidence` bucket | folder-scoped policies, 10 MB cap, MIME allow-list, signed URLs only |
| Edge Functions | `integrity-scan`, `share-evidence` | JWT verified server-side, secrets via `supabase secrets`, CORS |
| Sodabase | `integrity-scan` → MCP | `data_trust_health`, `check_rule`, `data_trust_scan`; verdicts rendered in product |

## How the judging criteria map

| Criterion | Where it shows |
|---|---|
| Data quality | Sodabase table verdicts + rule checks are first-class UI, not a checkbox. Consentra's own SQL rules run across 300 patients, not just the demo one. |
| Built to scale | Normalized per-provider rows, FHIR fields, `(patient_id, …)` indexes, RLS on every table, `SECURITY DEFINER` RPCs, idempotent upsert with fingerprints, edge function stateless. |
| Execution | Full loop: sign in → passport → scan → resolve → share → clinician view → revoke, all against live Supabase. |
| Craft | Same design system as the marketing site; side-by-side source cards; nothing merged silently. |

## Pitch (if top 3, 7:40 PM)

"Your records live in three hospitals and they don't agree. London has you on 10 mg, Boston on 20 mg, and the practice in Ithaca doesn't know you're allergic to penicillin. Consentra is the trust layer: one passport, every provider's copy, and a scan — powered by Sodabase on Supabase — that finds what's missing, stale or in conflict before a clinician relies on it. The patient resolves it, flags it, and shares a passport where anything unverified says so. Same Postgres, same RLS, 300 patients tonight, 300 million is the same schema."

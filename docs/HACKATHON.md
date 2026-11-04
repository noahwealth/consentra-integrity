# Consentra × Supabase × Sodabase — hackathon build (Nov 4, 2026)

**Positioning:** *the trust layer for fragmented healthcare data.* A patient's records live at several providers and don't agree. Consentra pulls every provider's copy into one passport, checks the underlying Supabase tables with Sodabase, shows conflicts side by side with source and timestamp, and shares a passport where unresolved questions are labeled — never silently merged.

What's new in this branch (nothing in `ios/` or `server/` changed):

| Path | What |
|---|---|
| `supabase/migrations/0001_init.sql` | Schema (FHIR-shaped, per-provider rows), indexes, RLS, RPCs, `detect_discrepancies()` cross-provider rules |
| `supabase/migrations/0002_evidence.sql` | **Storage**: private `evidence` bucket, RLS on `storage.objects` by patient folder, `evidence` table, share-scoped lookup |
| `supabase/migrations/0003_normalization.sql` | **Scale layer**: jurisdictions, cross-border corridors, canonical `drug_concepts` + `resolve_drug()`, `unit_conversions` + `dose_to_canonical()`, and a `detect_discrepancies()` that matches on concept rather than spelling |
| `supabase/migrations/0004_receipts_requests.sql` | **Consent ledger**: append-only `receipts` with a verifiable SHA-256 hash chain, `access_requests`, `verify_receipt_chain()` (owner-checked) |
| `supabase/migrations/0005_multitenant_demo.sql` | **Multi-tenant demo**: `claim_demo_patient()` clones the seeded template per visitor, so concurrent judges stop stealing one record |
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
   supabase db push --include-seed               # migrations 0001→0005, then supabase/seed.sql
   ```
   `db push` needs no database password — the CLI mints its own login role from your
   access token. The seed is declared in `supabase/config.toml` under `[db.seed]`, which
   is what `--include-seed` reads. (There is no `supabase db url` subcommand; and `psql`
   is not on PATH on a stock Mac — it ships with `libpq` at
   `/opt/homebrew/opt/libpq/bin/psql` — so the older `psql "$(supabase db url)"` recipe
   does not run as written.)

   **Order is permanent: 0001 → 0002 → 0003 → 0004 → 0005**, and the chain is five deep.
   0002 replaces `my_record()`/`get_share()` from 0001; 0003 replaces `detect_discrepancies()`;
   0004 replaces `my_record()` again and `evidence_for_share()`; 0005 replaces
   `claim_demo_patient()` and `request_access()`. Re-running an earlier file silently reverts
   every later definition with **no error anywhere**. Never re-run 0001; after re-running
   migration N, re-run every migration above N.

   Never apply anything from `supabase/seed/` to a hosted project: `_local_grants.sql`
   grants `anon` full access to every table and defeats the RLS this demo rests on. Those
   files are a plain-Postgres test rig only.

   Expect: `patients=301, patient_providers=595, medications=1046, allergies=394, conditions=615, observations=1511, immunizations=595`.
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
supabase secrets set SODABASE_TOKEN=<YOUR_SODABASE_MCP_TOKEN>            # never commit this
supabase functions deploy integrity-scan --use-api
supabase functions deploy share-evidence --use-api --no-verify-jwt
```

Test it (replace values; the JWT is any anonymous session token — easiest is to run a scan from the web app):

```bash
supabase functions logs integrity-scan --tail
```

If Sodabase's MCP responds with a shape the function doesn't recognise, the scan still completes with Consentra's own findings and the raw Sodabase payload is stored in `integrity_scans.summary.sodabase` — open the Integrity screen → "Sodabase notes" to see it, then adjust the field names in `runSodabase()`.

## 4. Web app (3 min)

1. Edit `web/config.js` with the Project URL and anon key (anon key is publishable; it's safe in the repo).
2. Local: `cd web && python3 -m http.server 8777` → http://localhost:8777. Note: the clinician page needs the `/s/:token` rewrite, so locally open `http://localhost:8777/share.html` only via Vercel, or use `vercel dev`.
3. Deploy: `cd web && vercel link --yes && vercel --prod --yes` (no prompts; framework "Other", root `./`).
   **Use the aliased URL, not the deployment URL.** The CLI labels the long
   `web-<hash>-<team>.vercel.app` as "Production", but it sits behind Vercel deployment
   protection and returns **302** to a login page. The `Aliased:` line is the one that
   returns 200 to an anonymous visitor — that is the live URL to submit.
4. Supabase → Authentication → URL Configuration → add the Vercel URL to **Site URL**/redirects (anonymous auth doesn't strictly need it, but it's one less thing).

## 5. Demo flow (record 60–90 s)

1. **iPhone, 15 s.** Existing app: connect Thameside → share allergies + labs → QR. "This is Consentra today."
2. **Web, Passport.** 3 providers, 32 records, banner "Not verified yet". Point at the two Lisinopril rows.
3. **Verify my health records.** Steps animate; six findings land from Consentra's own rules. The Sodabase panel fills with per-table trust chips — 7 watched clinical tables, currently 3 `untrusted`, 1 `trusted` and 3 `unknown` — so the screen shows 13 open items: 6 from Consentra's rules and 7 from Sodabase. Migrations 0006/0007 fixed root causes Sodabase flagged, which is why immunizations now reads `trusted`; the verdicts move as the data improves, so re-check this line against a live scan before recording.
4. **Resolve.** Penicillin: two providers have it, Lakeside doesn't. Lisinopril: 20 mg (Boston, Oct 21) vs 10 mg (London, Sep 2). Flag it with a note and **attach a photo** (any image: "Boston prescription label, 20 mg") — that's Storage.
5. **Share.** Create a 24 h share for Dr. Rivera, medications + allergies, open questions on. Open the clinician view: flagged rows say "in question", open questions listed with your note and the evidence link (signed URL, 10 min), UK units with US conversion. Revoke → page flips to "Access ended" within 5 s.

## 6. Submission checklist (by 6:45 PM)

- [ ] Repo public: published at https://github.com/noahwealth/consentra-integrity — verify it opens in an incognito window. Before publishing, the secrets gate below must pass.
- [ ] Secrets gate. Match credential *shapes*, not the words `sb_pat_`/`service_role` — those appear legitimately in `grant execute … to service_role`, in placeholders, and in this checklist itself, so a bare word-grep can never return empty. Shape matching needs no path exclusions and does not match its own definition:
  ```bash
  git grep -nIE 'sb_pat_[A-Za-z0-9_-]{16,}|sbp_[A-Za-z0-9]{36,}|sb_secret_[A-Za-z0-9_-]{16,}|postgres(ql)?://[a-zA-Z0-9_.-]+:[^@[:space:]]{8,}@'
  ```
  Empty = safe to publish. The publishable `sb_publishable_…` key in `web/config.js` is intentionally committed; it only works through RLS.
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
| Database | `supabase/migrations/0001–0005` | 19 tables, 3 canonical views, FKs, 15 explicit indexes (44 total incl. PK/unique), 6 enums, 7 triggers, 23 functions, 301-patient seed |
| RLS | all 19 tables + `storage.objects` | `owns_patient()` SECURITY DEFINER helper; every clinical table owner-scoped via generated `%I_owner` policies; anon reads only the public reference directories (`providers`, `jurisdictions`, `corridors`, `drug_concepts`, `unit_conversions`) — **zero patient rows**, verified from outside with the publishable key |
| Auth | anonymous sign-in → `claim_demo_patient()` | `web/app.js` `signInAnonymously`, SECURITY DEFINER claim |
| Storage | private `evidence` bucket | folder-scoped policies, 10 MB cap, MIME allow-list, signed URLs only |
| Edge Functions | `integrity-scan`, `share-evidence` | `integrity-scan` verifies the patient JWT server-side; `share-evidence` is token-authenticated in SQL (`evidence_for_share`, service-role only). Secrets via `supabase secrets`, CORS on both |
| Sodabase | `integrity-scan` → MCP | `data_trust_health`, `check_rule`, `data_trust_scan`; verdicts rendered in product |

## Known limitations (stated deliberately, not discovered on stage)

- **A patient row with any consent receipt cannot be deleted.** `receipts.patient_id` is
  `on delete cascade` and `receipts_no_update` raises unconditionally on DELETE, so the
  cascade aborts the parent delete. That is correct semantics for an append-only consent
  ledger — the ledger wins over the convenience of cleanup — but it means
  `prune_demo_clones()` cannot remove a clone that has transacted. It is service-role only
  and never called from the product.
- **Seed counts are seed-time values, not live invariants.** Since 0005 each visitor gets
  their own cloned record with its own clinical rows, so `patients`, `medications` and
  friends grow with every demo visitor. Verify counts against a freshly seeded project.
- **`unit_mismatch` is live but inert against this seed.** The rule ships in
  `detect_discrepancies()` and fires for 0 of 301 patients, because every multi-unit LOINC
  in the seed has both sides mapped in `unit_conversions`. It is scale architecture, not a
  finding the demo produces.
- **`request_access()` must be called with a share token, which is what the product does.**
  Called with the default demo code it resolves to the template patient, which no visitor
  owns, so `access_requests_owner` hides the request from everyone and the consent sheet
  never appears. The clinician page passes the share token instead, which identifies the
  visitor's own patient — verified live: with the default code the visitor sees 0 requests,
  with the token they see the clinician's. Any new caller must pass a token.

## How the judging criteria map

| Criterion | Where it shows |
|---|---|
| Data quality | Sodabase table verdicts and rule checks are first-class UI, not a checkbox. On top of them Consentra normalizes before it compares: RxNorm/ATC/dm+d ingredient crosswalk, LOINC+UCUM unit conversion including the affine HbA1c IFCC↔NGSP master equation, so a 10 mg London row and a 20 mg Boston row are compared as the same drug in the same unit. Measured across the live cohort: 20 provider spellings collapse onto 10 canonical ingredients, 327 (patient, ingredient) pairs exist at two or more providers, and 1,284 of 1,511 lab results arrive in a LOINC carrying two different units. |
| Built to scale | Normalized per-provider rows, FHIR fields, `(patient_id, …)` indexes, RLS on every table, `SECURITY DEFINER` RPCs, idempotent upsert with fingerprints, edge function stateless. |
| Execution | Full loop: sign in → passport → scan → resolve → share → clinician view → revoke, all against live Supabase. |
| Craft | Same design system as the marketing site; side-by-side source cards; nothing merged silently. |

## Pitch (if top 3, 7:40 PM)

"Your records live in three hospitals and they don't agree. London has you on 10 mg, Boston on 20 mg, and the practice in Ithaca doesn't know you're allergic to penicillin. Consentra is the trust layer: one passport, every provider's copy, and a scan — powered by Sodabase on Supabase — that finds what's missing, stale or in conflict before a clinician relies on it. The patient resolves it, flags it, and shares a passport where anything unverified says so. Same Postgres, same RLS, 300 patients tonight, 300 million is the same schema."

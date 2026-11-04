# Pitch — 7:40 PM, 3 minutes, live on the site

Set up before you walk up: the live URL open on **/#/passport** in a fresh incognito window (fresh visitor = fresh Noah, "Not verified"); a second tab ready for the clinician link; the iPhone unlocked on the Consentra app's Passport tab.

## 0:00 — the problem, phone in hand (20 s)
"This is Consentra today: a patient carries their records from a UK hospital and shares them with a US clinician by QR, from Apple Wallet." *(hold up the phone, don't demo it)*

"Here's what nobody solves. Noah's records live in three hospitals. London has him on 10 milligrams of lisinopril. Boston has him on 20. And the practice in Ithaca doesn't know he's allergic to penicillin. Every system you've heard of merges those into one record — and merging is where patients get hurt."

## 0:20 — Passport (15 s)
*(laptop)* "Three providers, 32 records, every provider's copy kept as its own row in Supabase — never merged. Not verified yet."

## 0:35 — Verify (30 s)
*(click Verify my health records; talk over the orb)* "Two layers. Consentra's rules run as SQL across every provider's copy — matched on RxNorm codes in canonical units, not on strings. And Sodabase watches the tables underneath: we call its MCP tools from an Edge Function — table trust, plain-language rules — and here are its verdicts — seven clinical tables, each with its own trust rating, as first-class findings next to ours."

*(findings land)* "Six. Critical: the missing penicillin allergy."

## 1:05 — Resolve (30 s)
*(open the lisinopril card)* "Side by side, with the source and the timestamp. 20 in Boston on October 21, 10 in London on September 2. He flags it — 'Boston raised my dose; London was never told' — and attaches the label photo. Private Storage bucket, RLS by patient folder."

## 1:35 — Share and the clinician (35 s)
*(Share → create for Dr. Rivera, meds + allergies → open clinician tab)* "The clinician sees what's verified plainly, what's in question labeled, his note, his evidence, and 48 millimoles per mol with 6.5 percent beside it. She wants labs too —" *(Request access on the clinician tab; back on Passport the consent sheet appears)* "— he drops one scope and allows. Nothing shared without his yes."

## 2:10 — Receipts and revoke (25 s)
*(Share page → Receipts → Verify chain)* "Every one of those events is a receipt: append-only, hash-chained, verifiable, exportable as a FHIR AuditEvent. And revoke —" *(click; switch to clinician tab)* "— gone in five seconds, signed URLs included."

## 2:35 — close (20 s)
"Sodabase tells us which tables to distrust. Consentra tells the patient which rows. You saw one dose conflict; run the same rule across all 301 patients and it finds 34 — thirty-four people whose providers disagree about a dose right now. Same schema at 301 patients or 300 million; RLS is the tenancy. Trust layer for fragmented healthcare data. Thank you."

## Likely questions
- **Real data?** Synthetic — 3 fictional providers, 301 fictional patients, faults planted so the demo is honest about what it detects. The schema is FHIR-shaped so a real SMART-on-FHIR source drops in.
- **Why both Sodabase and your own rules?** Different layers. Sodabase is table-level trust — stale, empty, wrong. Ours is row-level reconciliation across providers. The product shows both, labeled, and never merges.
- **Scale?** Set-based SQL rules, RLS tenancy, stateless Edge Functions, fingerprinted idempotent upserts. 712 findings across the cohort from one query.
- **HIPAA / privacy?** Private bucket, 10-minute signed URLs, revoke closes everything, append-only ledger. It's a demo, not a covered entity; the architecture is the one you'd audit.
- **What did the iOS app contribute tonight?** Context. Everything in the repo was written today; the phone shows there's a product this plugs into.
- **Normalization — why?** Because "Lisinopril" at Epic and "Lisinopril 10mg tablets" at the NHS are the same RxNorm ingredient, and HbA1c in mmol/mol and percent are the same LOINC code. National scale means matching by code; the schema carries seven jurisdictions and the cross-border corridor sizes.
- **If asked for the cohort numbers.** Run the rules over all 301 patients and they return, by kind: stale_medication 351, incomplete_provider 190, missing_allergy 117, **dose_conflict 34**, conflicting_status 19, duplicate_record 1, unit_mismatch 0. Lead with **34** — that is the headline rule finding thirty-four genuine cross-provider dose disagreements, not one planted fault.
  - Say *computed*, never *demonstrated*: `detect_discrepancies(p)` is per-patient and the edge function calls it only for the caller, so nothing in the product runs the cohort sweep. There is no button for it. "One query returns N" invites "show me."
  - Do **not** quote a coverage percentage. Every medication the generator writes is drawn from the same ten drugs `drug_concepts` defines, so resolution is 100% by construction — the fixture agreeing with itself, not a measurement. Claim the capability instead: the RxNorm/ATC/dm+d crosswalk and the affine HbA1c IFCC↔NGSP conversion are applied on every comparison. 20 provider spellings do collapse onto 10 ingredients, and 327 (patient, ingredient) pairs sit at two or more providers — but that is the *comparison surface*, not problems found, so only use it if you label it as such.
  - stale_medication is relative to `now()`, so these totals rise ~1/day. Quote them as "today", or not at all.

## If something breaks on stage
- Scan hangs → "Sodabase is warming up; here's the last scan" → go to /#/resolve (findings persist).
- Clinician tab doesn't flip on revoke → refresh it; say "the page polls every five seconds."
- Wi-Fi dies → the video.

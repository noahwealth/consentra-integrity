# Consentra

## Hackathon build: global health data integrity (Supabase × Sodabase)

## BEST VIEWED IN MOBILE WINDOW PANE SIZE - BUILT FOR MOBILE USE w/ APPLE WALLET FEATURES (SWIFT APP BUILT AS WELL IF INTERESTED LET NOAH KNOW :) 

**Live:** <https://web-sage-alpha-25.vercel.app> ·  · **Details:** [`docs/HACKATHON.md`](docs/HACKATHON.md)

A patient's records live at several providers and disagree. Consentra pulls every provider's copy into one passport, checks the underlying Supabase tables with Sodabase, and shows conflicts side by side with source and timestamp — never silently merged.

**Supabase** — Postgres schema with RLS on every table (`supabase/migrations`, 0001→0005), anonymous auth into `claim_demo_patient()` (each visitor gets their own cloned record), Storage (private `evidence` bucket, folder-scoped policies, signed URLs), append-only consent receipts with a verifiable hash chain, and two edge functions (`supabase/functions/integrity-scan`, `supabase/functions/share-evidence`). Anon reads zero patient rows — only the public reference directories.

**Sodabase** — watches the clinical tables; the scan calls its MCP tools (`data_trust_health`, `check_rule`, `data_trust_scan`) and renders the verdicts as first-class UI, not a checkbox.

---

Patient-controlled sharing of medical records for international travelers receiving care in the US. The patient connects their home hospital, picks exactly what to share and for how long, and shows a QR code or Apple Wallet pass. The clinician opens a read-only page in any browser, and the patient can revoke access at any time.

The reasons behind every choice are in [`decision.md`](decision.md). The design is in `docs/superpowers/specs/`.

## What's here

| Path | What |
|---|---|
| `server/` | Node + Express. Fake UK hospital source (FHIR R4-shaped), share store, patient API, clinician page and Wallet pass signing. |
| `ios/` | SwiftUI iOS 17 app (XcodeGen). Passport, Health, Share and Activity tabs. |
| `scripts/make-pass-csr.sh` | Creates the Wallet signing key and CSR (one-time). |
| `scripts/make-pass-icons.mjs` | Regenerates the pass images and app icon. |

## Run it

> **New to the project?** Follow the step-by-step guide in [`docs/LOCAL_DEVELOPMENT.md`](docs/LOCAL_DEVELOPMENT.md). It covers setup, certificates (you don't need any to start), running on a real iPhone, tests and troubleshooting.

**Requirements:** Xcode 15.4+, Node 20+, XcodeGen (`brew install xcodegen`).

```bash
# 1. Server (prints the LAN address that share links will use)
cd server && npm install && npm start

# 2. App
cd ios && xcodegen && open Consentra.xcodeproj   # run on an iPhone 15 Pro simulator
```

- **Simulator:** the app talks to `http://localhost:3000` by default.
- **Real iPhone:** tap the avatar, then Settings, and enter the address the server printed, e.g. `http://10.56.1.197:3000`.
- **Clinician device:** a phone or laptop that scans the QR must be on the **same Wi-Fi** as the Mac.

**Wallet signing:** this needs `server/certs/pass.pem`, `pass.key` and `wwdr.pem`. They're gitignored. Other developers ask Ali for the existing files rather than creating new ones (see docs/LOCAL_DEVELOPMENT.md §4 and decision.md D11). Without certificates, everything still works except the "Add to Apple Wallet" button, which is hidden.

**Reset the demo to a fresh, disconnected patient:**

```bash
lsof -ti tcp:3000 | xargs kill; rm -f server/data/state.json; (cd server && npm start)
```

## Demo script (about 3 minutes)

1. **Setup.** Noah Dixon, from London, is about to see a US doctor. His records are back home at Thameside General. The Passport tab shows "Connect your records".
2. **Connect.** Tap Connect your records, then Thameside General 🇬🇧, then Sign in, then Allow. 18 records arrive.
3. **Choose what to share.** Go to the Share tab, then With a Provider. Type "Dr. Rivera, Mass General", tick **Allergies** and **Lab Results**, choose 24 h, and tap Create Share. Nothing is shared by default.
4. **Present.** A QR code appears with a countdown. Tap **Add to Apple Wallet** to add a real signed pass that expires with the share.
5. **Clinician view.** Scan the QR with another phone. The browser shows only allergies and labs, with UK units next to US conversions (`HbA1c 48 mmol/mol · US: 6.5 %`). No app, no login. Back on the patient's phone, Manage this share shows "Opened on iPhone" within 5 seconds.
6. **Revoke.** Tap Revoke Access and confirm. Within 5 seconds the clinician's open page changes to **"Access ended"**, and the Wallet pass's QR leads to the same page. Activity shows the share being created, viewed and revoked.

## Tests

```bash
cd server && npm test        # 25 tests: API, validation, clinician filtering, expiry/revoke, pass signing
cd ios && xcodebuild test -scheme Consentra -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:ConsentraTests
```

`ConsentraUITests` walks the whole demo (connect → share → present → Wallet sheet → revoke). It needs a running server with fresh state. `testRevokeFromManageAccess` also needs something opening the share link, playing the clinician. Set `TEST_RUNNER_SCREENSHOT_DIR=/some/dir` to save a screenshot of each step.

## Not in this MVP

There are no patient accounts, no encryption at rest, plain HTTP on the LAN, a simulated hospital sign-in and no translation. See decision.md D8–D9.

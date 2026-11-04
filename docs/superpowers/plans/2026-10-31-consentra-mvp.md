# Consentra MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a demoable flow: the patient connects a fictional UK hospital, shares selected categories for a set time as a QR code / signed Wallet pass, a clinician views that subset in a browser, and the patient revokes.

**Architecture:** A local Node/Express server holds the fake FHIR source, the share store (JSON file), the patient API, the server-rendered clinician page and `.pkpass` signing. A SwiftUI iOS 17 app (XcodeGen) is a thin client of that API.

**Tech Stack:** Node 26, Express 4, passkit-generator 3, `node:test` and built-in `fetch`; Swift 5.10, SwiftUI, PassKit, CoreImage, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-31-consentra-mvp-design.md`, plus `decision.md` (D1–D9).

## Global Constraints

- The server listens on `0.0.0.0:3000`. Share URLs use the Mac's LAN IPv4 (`http://<ip>:3000/s/<token>`).
- Tokens are 16 random bytes, base64url.
- A share is active iff `revokedAt == null && now < expiresAt`.
- Categories, exactly: `medications`, `allergies`, `conditions`, `labs`, `immunizations`.
- `durationHours` must be one of `1, 24, 168, 720`.
- Pass certificates live in `server/certs/`: `pass.pem`, `pass.key`, `wwdr.pem`. The Pass Type ID and Team ID are parsed from the `pass.pem` subject (`UID=`, `OU=`).
- The source is fictional: "Thameside General Hospital, London, UK". The patient is Noah Dixon.
- Unit conversions:
  - glucose mmol/L × 18.016 → mg/dL
  - HbA1c mmol/mol → % = 0.0915·v + 2.15
  - cholesterol mmol/L × 38.67 → mg/dL
  - creatinine µmol/L ÷ 88.4 → mg/dL
- iOS: deployment target 17.0, bundle id `com.aliabdullah.consentra`, no third-party Swift packages, `NSAppTransportSecurity.NSAllowsLocalNetworking = true`.
- `server/certs/*` and `server/data/` are never committed.

## Review Focus

1. **Unshared category leaks into the clinician page.** Neither the HTML nor any JSON may contain items from unpicked categories. Test: `clinician page omits unshared categories` (Task 2).
2. **Garbage, unknown, revoked or expired token.** Each must give the same "Access ended" page with status 410, no 500, and no category names. Tests: `unknown token → 410 access ended`, `expired share → 410` (Task 2).
3. **Bad share request** (empty categories, unknown category, duration not in the list) must return 400 and create nothing. Test: `rejects invalid share requests` (Task 1).
4. **Revoking twice** must be idempotent (200, `revokedAt` unchanged). Revoking an unknown token gives 404. The pass for a revoked share gives 410. Tests in Tasks 1 and 3.
5. **Server unreachable from the app** must show an inline error with a Retry button, never an endless spinner. Checked manually in Task 4 by stopping the server.

---

### Task 1: Server core (source data, units, share store, patient API)

**Files:**
- Create:
  - `server/package.json` (`"type":"module"`; scripts `start`, `test`)
  - `server/src/app.js`
  - `server/src/source/thameside.js`
  - `server/src/source/display.js`
  - `server/src/units.js`
  - `server/src/store.js`
  - `server/src/net.js`
  - `server/index.js`
- Test: `server/test/api.test.js`, `server/test/units.test.js`

**Interfaces — Produces:**
- `createApp({ dataFile: string, certsDir: string, baseUrl?: string }) → express.Application`. Tests use a temp `dataFile`.
- `thameside.js` exports `patient` (FHIR Patient) and `resources`, shaped `{ medications: MedicationStatement[], allergies: AllergyIntolerance[], conditions: Condition[], labs: Observation[], immunizations: Immunization[] }`.
- `toDisplayItem(category, resource) → { id, title, detail, date|null, value|null, unit|null, usValue|null, usUnit|null }`.
- `toUS(loincCode, value, unit) → { value, unit } | null`, covering LOINC `15074-8` glucose, `59261-8` HbA1c, `14647-2` cholesterol and `14682-9` creatinine.
- `Store(dataFile)` with:
  - `getState()`
  - `connectSource() → source`
  - `createShare({ categories, durationHours, label }) → share`
  - `listShares() → share[]`
  - `getShare(token)`
  - `revoke(token) → share | null`
  - `logView(token, userAgent)`
  - `status(share) → 'active' | 'expired' | 'revoked'`
- `lanIp() → string`
- **JSON shapes** (the app decodes these):
  - Share: `{ token, label, categories: string[], createdAt, expiresAt, revokedAt: string|null, status, url, views: [{ at, userAgent }] }`, with ISO-8601 dates.
  - `POST /api/shares` also returns `walletAvailable: boolean`.
  - `GET /api/record` returns `{ patient: { name, birthDate, homeCountry }, source: { id, name, city, country, connected, lastSynced|null }, categories: { [cat]: DisplayItem[] } }`. `categories` is empty until connected.
  - `POST /api/source/connect` returns `{ source, counts: { [cat]: number } }`.

- [ ] **Step 1: Write failing tests**
  - `units.test.js`:
    - `toUS('59261-8', 48, 'mmol/mol')` gives value 6.5 (to 1 dp) and unit `'%'`.
    - Glucose 5.5 mmol/L gives 99 mg/dL (rounded).
    - An unknown code gives `null`.
  - `api.test.js` starts `createApp` on port 0 with a temp file and covers:
    - `connect then record lists 5 categories`
    - `creates share with url and status active` (url matches `/\/s\/[A-Za-z0-9_-]{22}$/`)
    - `rejects invalid share requests`: `[]`, `['xrays']`, `durationHours: 5` each give 400, and `GET /api/shares` stays empty.
    - `revoke is idempotent`: the second call returns 200 and the same `revokedAt`.
    - `revoke unknown → 404`
    - `shares persist across app instances`: a new `createApp` on the same file lists the share.
- [ ] **Step 2: Run tests and confirm they fail.** Run `cd server && npm i express@4 passkit-generator@3 && node --test`. Expected: FAIL (modules missing).
- [ ] **Step 3: Implement.**
  - Fake record: 4 meds (UK names, e.g. Ramipril 5 mg, Metformin 500 mg, Atorvastatin 20 mg, Salbutamol inhaler), 2 allergies (Penicillin anaphylaxis, peanut), 3 conditions (T2 diabetes, hypertension, asthma), 5 labs (HbA1c 48 mmol/mol, glucose 7.2 mmol/L, total cholesterol 5.1 mmol/L, creatinine 88 µmol/L, eGFR 82), 4 immunizations.
  - The store writes the whole state with `writeFileSync` after each mutation.
  - `index.js` calls `createApp({ dataFile: 'data/state.json', certsDir: 'certs' })` and logs the clinician base URL.
- [ ] **Step 4: Run `node --test`.** Expected: all pass.
- [ ] **Step 5: Commit** with `feat(server): fake UK source, share store, patient API`.

### Task 2: Clinician page

**Files:**
- Create: `server/src/clinician.js` (exports `renderShare(record, share) → html` and `renderEnded() → html`)
- Modify: `server/src/app.js` (adds `GET /s/:token` and `GET /s/:token/status`)
- Test: `server/test/clinician.test.js`

**Interfaces:**
- Consumes `Store` and `toDisplayItem` from Task 1.
- Produces:
  - `GET /s/:token`: 200 HTML when active (logs a view), otherwise 410 with the `renderEnded()` HTML.
  - `GET /s/:token/status`: `{ active: boolean }`, plus 410 when inactive.

- [ ] **Step 1: Write failing tests**
  - `clinician page omits unshared categories`: share `['allergies','labs']`. The HTML contains `Penicillin` and `6.5%` but not `Ramipril` or `Medications`.
  - `unknown token → 410 access ended`: the body contains `Access ended` and none of the 5 category names.
  - `expired share → 410`: create a share, set `expiresAt` in the past via the store, then GET.
  - `view is logged`: after a GET, `GET /api/shares` shows `views.length === 1`.
  - `revoked → status inactive`
- [ ] **Step 2: Run `node --test`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Self-contained HTML/CSS styled like the Figma: system font, grouped white cards on `#F2F2F7`, Consentra gradient header.
  - Header: patient name, DOB, "Home country: United Kingdom", source name, then "Shared by patient · read-only · expires in …".
  - Labs render as `original (US value)`.
  - An inline `<script>` polls `status` every 5000 ms. When it sees 410 it replaces `document.body` with the ended markup.
  - Escape all interpolated strings.
- [ ] **Step 4: Run `node --test`.** Expected: pass.
- [ ] **Step 5: Manual check.** Run `npm start`, create a share with curl, open it in Safari, revoke with curl, and confirm the page flips within 5 s.
- [ ] **Step 6: Commit** with `feat(server): clinician read-only view with live revoke`.

### Task 3: Wallet pass signing

**Files:**
- Create:
  - `server/src/pass.js`
  - `server/pass-model/consentra.pass/pass.json`
  - `icon.png`, `icon@2x.png`, `logo.png`, `logo@2x.png`
  - `scripts/make-pass-icons.mjs` (writes solid/gradient PNGs with `zlib`, no deps)
- Modify: `server/src/app.js` (adds `GET /api/shares/:token/pass.pkpass`; `walletAvailable` = certs present)
- Test: `server/test/pass.test.js`

**Interfaces:**
- Produces `certInfo(certsDir) → { passTypeIdentifier, teamIdentifier } | null`, parsed with `crypto.X509Certificate` from `subject`.
- Produces `buildPass({ share, patient, certsDir }) → Promise<Buffer>`. The pass is generic and contains:
  - `serialNumber = token`
  - `barcodes: [{ format: 'PKBarcodeFormatQR', message: share.url, messageEncoding: 'iso-8859-1' }]`
  - `expirationDate = share.expiresAt`
  - primary field: patient name
  - secondary fields: categories, expires
  - back field: "Revoke anytime in the Consentra app"
  - `backgroundColor rgb(88,86,214)` and white foreground

- [ ] **Step 1: Write failing tests**
  - `certInfo reads ids from cert` gives `pass.com.aliabdullah.consentra` / `YRL45Q79LJ`. Skip if no certs.
  - `pkpass is a zip with signature`: the buffer starts with `PK`, and unzipping (`unzip -l` via child_process) lists `pass.json`, `manifest.json` and `signature`.
  - `revoked share pass → 410`
- [ ] **Step 2: Run `node --test`.** Expected: FAIL.
- [ ] **Step 3: Implement** with `PKPass.from({ model, certificates: { wwdr, signerCert, signerKey } }, overrides)`. Run `node ../scripts/make-pass-icons.mjs` once to create the PNGs.
- [ ] **Step 4: Run `node --test`.** Expected: pass. Then download a pass with curl and open it in the iOS Simulator with `xcrun simctl openurl booted http://localhost:3000/api/shares/<t>/pass.pkpass`. Wallet should show an "Add" sheet.
- [ ] **Step 5: Commit** with `feat(server): signed Apple Wallet pass per share`.

### Task 4: iOS app scaffold, API client, Passport Home, Connect flow

**Files:**
- Create:
  - `ios/project.yml`
  - `ios/Consentra/ConsentraApp.swift`
  - `ios/Consentra/Models.swift`
  - `ios/Consentra/API.swift`
  - `ios/Consentra/AppModel.swift`
  - `ios/Consentra/Theme.swift`
  - `ios/Consentra/Views/RootTabs.swift`
  - `ios/Consentra/Views/PassportHomeView.swift`
  - `ios/Consentra/Views/ConnectFlow.swift`
  - `ios/Consentra/Views/MyHealthView.swift`
  - `ios/Consentra/Views/SettingsView.swift`
  - `ios/Consentra/Info.plist`
- Test: build only. `ios/ConsentraTests/ModelsTests.swift` checks that `Share` decodes the Task 1 JSON fixture.

**Interfaces:**
- Consumes the Task 1 JSON shapes.
- Produces:
  - `struct Share: Codable, Identifiable` (`id` = `token`) and `enum ShareStatus: String { active, expired, revoked }`.
  - `struct HealthRecord`, `DisplayItem`, `SourceInfo`.
  - `enum Category: String, CaseIterable`. It has the 5 raw values with `title`, `symbol` (SF Symbol) and `tint`.
  - `API(baseURL: URL)` with these async throwing methods:
    - `record() → HealthRecord`
    - `connect() → SourceInfo`
    - `createShare(categories: [Category], durationHours: Int, label: String) → (Share, walletAvailable: Bool)`
    - `shares() → [Share]`
    - `revoke(token: String) → Share`
    - `passData(token: String) → Data`
  - `@Observable final class AppModel` with `record`, `shares`, `error: String?`, `baseURL` (stored in UserDefaults, default `http://localhost:3000`), and `func refresh() async`.

- [ ] **Step 1:** Write the `ModelsTests` decoding test, using a JSON literal copied from the Task 1 response. Use ISO-8601 with fractional seconds (`.iso8601` plus a custom formatter fallback).
- [ ] **Step 2:** Run `cd ios && xcodegen && xcodebuild test -scheme Consentra -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`. Expected: FAIL (types missing).
- [ ] **Step 3: Implement.**
  - Tabs: Passport, Health, Share, Activity. Share and Activity are placeholders until Tasks 5 and 6.
  - Passport Home (Figma 09): gradient card, stats, quick actions, and a "Connect your records" CTA when not connected.
  - Connect flow (Figma 22–25): list with Thameside General 🇬🇧, then a fake sign-in (prefilled NHS number, Continue), then authorize (scopes list), then "Connected", which calls `connect()` and `refresh()`.
  - My Health (Figma 10): categories with counts, then a list of items.
  - Any `AppModel.error` shows an inline banner with Retry.
- [ ] **Step 4:** Run the tests: PASS. Then run the app in the simulator, connect, and check that the counts appear. Stop the server and check that the error banner shows.
- [ ] **Step 5: Commit** with `feat(ios): app shell, API client, passport home, connect flow`.

### Task 5: Share, Present (QR), Add to Wallet

**Files:**
- Create:
  - `ios/Consentra/Views/ShareView.swift`
  - `ios/Consentra/Views/PresentView.swift`
  - `ios/Consentra/QR.swift`
  - `ios/Consentra/AddPassButton.swift`
- Modify: `RootTabs.swift` (Share tab)

**Interfaces:**
- Consumes `API.createShare` and `API.passData`.
- Produces `QR.image(for: String) → UIImage?` (CoreImage `CIQRCodeGenerator`, correction "M", nearest-neighbour upscaling).

- [ ] **Step 1: Implement ShareView** (Figma 18).
  - 5 toggles, all off by default.
  - Duration picker with 1 h / 24 h / 7 d / 30 d, default 24 h.
  - Optional label field.
  - "Create share" is disabled when nothing is selected. Tapping it pushes PresentView.
- [ ] **Step 2: Implement PresentView** (Figma 19).
  - QR of `share.url`, the label, the list of categories, and a live countdown (`TimelineView`).
  - `AddPassButton`, a `UIViewRepresentable` wrapping `PKAddPassButton`. It fetches `passData`, builds `PKPass(data:)` and presents `PKAddPassesViewController`. It is hidden when `walletAvailable == false`.
  - `ShareLink(item: share.url)`.
- [ ] **Step 3: Verify in the simulator.** Create a share, scan the QR on screen with a real phone camera (or open the URL in Mac Safari), and confirm only the chosen categories show. Tap Add to Apple Wallet and confirm the pass appears in Wallet.
- [ ] **Step 4: Commit** with `feat(ios): share builder, QR presentation, add to Wallet`.

### Task 6: Access management, revoke, Activity

**Files:**
- Create: `ios/Consentra/Views/AccessListView.swift`, `ios/Consentra/Views/AccessDetailView.swift`, `ios/Consentra/Views/ActivityView.swift`
- Modify: `PassportHomeView.swift` (Manage Access → AccessListView), `RootTabs.swift` (Activity tab)

- [ ] **Step 1: AccessListView** (Figma 15): sections Active / Ended, rows showing label, categories and status chip, plus pull to refresh.
- [ ] **Step 2: AccessDetailView** (Figma 16/17): categories, created, expires, a list of views ("Opened · 2 min ago"), and a red "Revoke access" button with `confirmationDialog`. Revoking calls `API.revoke` and `refresh()`.
- [ ] **Step 3: ActivityView** (Figma 26): events derived from shares (created, each view, revoked), sorted newest first.
- [ ] **Step 4: Verify the full demo.** Share → open on another device → revoke in the app → the clinician page shows "Access ended" within 5 s.
- [ ] **Step 5: Commit** with `feat(ios): access management, revoke, activity`.

### Task 7: Demo polish and README

**Files:** Create `README.md` (run steps and a demo script). Update `decision.md` with any calls made during the build.

- [ ] **Step 1: Write the README.**
  - Run `cd server && npm i && npm start`, then `cd ios && xcodegen && open Consentra.xcodeproj`.
  - Phones scanning the QR must be on the same Wi-Fi.
  - Include a demo script with 6 beats.
- [ ] **Step 2:** Run `node --test` and the iOS tests. Both must be green.
- [ ] **Step 3: Commit** with `docs: README and demo script`.

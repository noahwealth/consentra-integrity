# Consentra — Decision Log

Each entry records what was picked, why, and what else was on the table.
**Decided by:** *Ali* = you chose it; *Claude* = my call, open for you to overturn.

---

## D1 · Demo story: share → view → revoke
**Decided by:** Ali · 2026-10-31

The MVP shows one complete path: the patient connects a source, chooses categories and an expiry, then presents a QR code / Wallet pass. The clinician opens a browser view, and the patient revokes access.

**Alternatives:**
- Provider-initiated request with lock-screen approval (Figma 04–08). More polished, but needs a request flow on the clinician side.
- Emergency card first. Simpler, but doesn't show limit, expire and revoke.

---

## D2 · Backend: local Node server on the Mac
**Decided by:** Ali · 2026-10-31

A small Express server holds shares, enforces expiry and revoke, serves the clinician page and signs Wallet passes. Any device on the same Wi-Fi can scan the QR and open the page.

**Alternatives:**
- Hosted (Vercel/Fly). Reachable from anywhere, but setting it up eats into the hour.
- No server, with the data encoded in the link. Then revoke can't be enforced, which breaks the core promise.

---

## D3 · Fake source: a fictional UK hospital, records in English
**Decided by:** Claude (country), Ali (English only) · 2026-10-31

The source is **"Thameside General Hospital, London"**, which is fictional so no real organisation is impersonated. It returns FHIR R4-shaped JSON covering medications, allergies, conditions, lab results and immunizations. The patient is **Noah Dixon**, matching the Figma mockups.

**Why the UK:** The records are already in English, so translation isn't needed, but the data is still meaningfully foreign to a US clinician. Labs use **mmol/L and mmol/mol** where the US uses mg/dL and %, drugs carry **UK brand/generic names**, and dates are day-first. The clinician view shows the original value and a US conversion beside it, e.g. `HbA1c 48 mmol/mol (6.5%)`. That makes the traveler story visible at almost no extra cost.

**Alternatives:**
- India (Apollo-style hospital). A big medical-travel market, but units are mostly US-style already, so the international angle is weaker.
- A US Epic/NYU source as in Figma. Matches the mockups but loses the traveler story.
- A non-English source with translation. Ali chose English only for now.

---

## D4 · Wallet pass signing: on the server, certificate created by a script
**Decided by:** Claude · 2026-10-31

**What I found:** This Mac has no Pass Type ID certificate. The Keychain holds only Apple's WWDR intermediate CA and no signing identities. Wallet refuses unsigned passes, so a certificate has to be created.

**Pick:**
1. `scripts/make-pass-csr.sh` uses `openssl` to generate a private key and a CSR in `server/certs/` (gitignored). The private key never enters the Keychain and never leaves the repo folder.
2. You do about five minutes in the Apple Developer portal: create a Pass Type ID (`pass.<you>.consentra`), upload the CSR, and download `pass.cer` into `server/certs/`.
3. The server signs each `.pkpass` with the `passkit-generator` npm library. It reads the **Team ID and Pass Type ID directly from the certificate**, so there's nothing to type in.
4. **Fallback:** if no certificate is present, the server says so and the app hides "Add to Apple Wallet" and shows the same pass as an in-app card with the QR. The demo never blocks on Apple's portal.

**Why on the server:** Signing needs the private key. Putting it in the iPhone app would ship the key to every user, so signing on the server is the standard approach and the only safe one.

**Alternatives:**
- Export a `.p12` from Keychain Access. That works if the certificate already exists on some Mac, but here it doesn't, and the openssl route skips the Keychain GUI entirely.
- Sign in-app. Rejected because it exposes the private key.
- A third-party pass service (PassKit.io, Passcreator). It costs money and sends health data to another vendor.
- Simulate the pass only. This is kept as the automatic fallback, not the main path.

---

## D5 · One Wallet pass per share, not one long-lived "Health Passport" pass
**Decided by:** Claude · 2026-10-31

Each share produces its own pass. The QR encodes that share's URL, and the pass's `expirationDate` matches the share's expiry, so Wallet greys it out by itself.

**Why:** A single persistent pass whose QR changes needs Apple's pass web-service and an APNs push certificate to update it, which is too much for an hour. Revoke is enforced on the server, so a revoked pass still sitting in Wallet just leads to an "access ended" page.

**Alternatives:**
- A persistent pass with push updates, as in Figma 02/03. This is the right long-term design, deferred for now.

---

## D6 · iOS app: SwiftUI, iOS 17, XcodeGen
**Decided by:** Claude · 2026-10-31

The project is defined in `ios/project.yml` and generated with XcodeGen (already installed). SwiftUI with `@Observable`, async/await `URLSession`, and `PassKit` for `PKAddPassesViewController`. QR codes come from CoreImage, so there are no third-party Swift packages.

**Why:** It matches the installed toolchain (Xcode 15.4 / iOS 17 SDK). A YAML project file is easy to diff and regenerate, unlike a hand-edited `.pbxproj`.

**Alternatives:**
- A hand-made Xcode project.
- Tuist (not installed).
- UIKit (slower to build screens like the mockups).

---

## D7 · Clinician view: server-rendered HTML, polling for revoke
**Decided by:** Claude · 2026-10-31

`GET /s/:token` returns one self-contained HTML page with no framework and no login. The token is a random 128-bit value; holding the link is the permission. The page re-checks the share every 5 seconds, so a revoke shows up live during the demo. Every view is logged so the patient can see when it was opened.

**Alternatives:**
- A React/Vite front end. Unneeded weight for a single read-only page.
- WebSockets. Polling is simpler and fast enough for a demo.

---

## D8 · Networking: plain HTTP on the LAN, URL built by the server
**Decided by:** Claude · 2026-10-31

The server listens on `0.0.0.0:3000`, detects the Mac's LAN IP, and builds share URLs with it, so a QR scanned by a real phone works. The app reaches the server at a base URL set in Settings (default `http://localhost:3000` on the simulator). Its `Info.plist` sets `NSAllowsLocalNetworking`.

**Risk, accepted for the demo:** Health data travels over unencrypted HTTP on your Wi-Fi. Production needs HTTPS (and a hosted server, see D2).

---

## D9 · Out of scope for the MVP (on purpose)
**Decided by:** Claude · 2026-10-31

- Patient sign-in and accounts. There's one hard-coded demo patient.
- Encryption at rest and HIPAA / GDPR compliance work.
- Real FHIR / SMART-on-FHIR OAuth. The provider sign-in screen is a fake approval.
- Translation and multiple languages (D3).
- Wallet pass push updates (D5).
- Figma screens outside D1's path: lock-screen request, Face ID, emergency, Health Link, side-button.

Persistence is a JSON file (`server/data/shares.json`), so shares survive a server restart. SQLite would be the next step.

---

## D10 · Calls made during the build
**Decided by:** Claude · 2026-10-31

These are smaller calls, each recorded so you can overturn it.

- **Dates are shown as "22 Sep 2026"** on the clinician page and in the app. A UK patient writes 12/04/1988 and a US clinician reads it as December 4th, so spelled-out months avoid that trap.
- **Lab results show the original UK value first and the US conversion under it.** The original is the source of truth, and the conversion is a convenience that is labeled "US:".
- **Severe allergies are highlighted in red** on the clinician page (Penicillin, anaphylaxis). It's the single most safety-critical line on the page.
- **The QR code uses the highest error correction level (H)** so the Consentra logo can sit in the middle. A test confirms it still decodes to the exact share URL.
- **Unshared categories are never sent to the browser.** Filtering happens on the server, not by hiding things on the page. A test checks that unshared items like Ramipril never appear in the HTML.
- **Unknown, revoked and expired links all return the same "Access ended" page** (HTTP 410). It doesn't reveal whether the link ever existed or what it contained.
- **Sharing before connecting a source is refused** (HTTP 409).
- **The clinician page re-checks every 5 seconds, and so do the app's Access Detail and Activity screens while open.** Revokes and views therefore show up live during the demo.
- **The hospital list includes four fictional international hospitals marked "Coming soon"** (Toronto, Madrid, Sydney, Cologne), to show the traveler story without impersonating real organisations.
- **XcodeGen's project format is pinned to Xcode 15.3.** XcodeGen 2.46 writes the Xcode 16 format by default, which this Mac's Xcode 15.4 can't open.
- **The demo flow is covered by an automated UI test** (XCUITest) that walks connect → share → Wallet → revoke and saves screenshots.

---

## D11 · Developers share one Wallet certificate; certificates are optional for development
**Decided by:** Claude · 2026-11-01

**Pick:** Developers don't need a certificate to work on Consentra. Without one, the server hides the Wallet button and everything else works (D4 fallback). Developers who work on the pass itself get the team's single Pass Type ID certificate and key (`pass.pem`, `pass.key`, `wwdr.pem`) by asking Ali, who hands them over directly (e.g. AirDrop). The files go in `server/certs/`, which is gitignored.

**Why:**
- A pass's signature only has to chain to Apple. The Pass Type ID (`pass.com.aliabdullah.consentra`) is what identifies the pass. Per-developer certificates for the same ID would give identical behaviour with more to manage.
- Creating certificates in the Apple portal needs the Account Holder or Admin role, which most developers won't have.
- Each certificate on the Apple account is another credential that could leak and has to be revoked.

**Alternatives:**
- **One certificate per developer.** You'd create one for each person from their own key. Useful only if you need to revoke one person's access on its own. Overkill for a small team.
- **A shared "pass signing" server in the cloud.** Developers would never hold the key at all. This is the right setup once the server is hosted (see the TestFlight discussion and D2). Until then it adds infrastructure.
- **Commit the certificates.** Rejected, because it would put a private key in git history.

**Risk:** everyone holding the key can sign passes as Consentra. If it leaks, revoke the certificate in the portal, create a new one with `scripts/make-pass-csr.sh`, and redistribute.

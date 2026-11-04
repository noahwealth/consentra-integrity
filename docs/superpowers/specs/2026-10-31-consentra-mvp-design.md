# Consentra MVP — Design

Decisions and their alternatives live in `/decision.md` (D1–D9). This doc describes what gets built.

## Intent

International travelers getting care in the US arrive with records the US clinician can't easily see. Consentra lets the patient carry those records on their iPhone, pick exactly what to share and for how long, and hand it over as a QR code / Apple Wallet pass. The clinician sees only that subset in a browser, with nothing to install, and the patient can take access back at any time.

**Success (1-hour demo):** On camera, the patient connects their London hospital, shares 3 of 5 categories for 24 h, and adds the pass to Wallet. A second device scans it and sees exactly those 3 categories with US unit conversions. The patient taps Revoke, and within about 5 s the clinician's page reads "Access ended".

**Anti-goals:**
- The clinician sees a category the patient didn't pick.
- A revoked or expired link still shows data.
- The private signing key is anywhere but the server folder.

## Parts

### 1. Server (`server/`, Node 26 + Express)

**Data**
- `src/source/thameside.js` holds the fictional Thameside General Hospital record for Noah Dixon, as FHIR R4-shaped resources grouped into 5 categories:
  - `medications` (4, UK names)
  - `allergies` (2)
  - `conditions` (3)
  - `labs` (5, UK units)
  - `immunizations` (4)
- `src/units.js` converts glucose mmol/L→mg/dL (×18.016), HbA1c mmol/mol→% (`0.0915×v + 2.15`), cholesterol mmol/L→mg/dL (×38.67) and creatinine µmol/L→mg/dL (÷88.4).

**Share model**
```
{ token, categories[], expiresAt, createdAt, revokedAt|null, label, views[] }
```
- Stored in `data/shares.json` (gitignored).
- `token` is 16 random bytes, base64url.
- A share is **active** iff `revokedAt == null && now < expiresAt`.

**Patient API** (no auth, single demo patient; see D9)

| Endpoint | Behaviour |
|---|---|
| `POST /api/source/connect` | Marks Thameside connected. Returns the summary: counts per category and last-synced time. |
| `GET /api/record` | Full record grouped by category, used by the app's Health tab. |
| `POST /api/shares` | Takes `{categories, durationHours, label}` and returns the share plus `url` (LAN IP) and `walletAvailable`. |
| `GET /api/shares` | Lists shares with status (`active` / `expired` / `revoked`) and their views. |
| `POST /api/shares/:token/revoke` | Revokes the share. |
| `GET /api/shares/:token/pass.pkpass` | Returns the signed pass (D4/D5), or 503 with a reason if there's no certificate. |

**Clinician**

| Endpoint | Behaviour |
|---|---|
| `GET /s/:token` | Self-contained HTML. If active: patient header, "Shared by patient · read-only · expires in …", then only the shared categories. Labs show the original value plus the US conversion. Each load is logged to `views`. If inactive or unknown: an "Access ended" page with no data and no hint of which categories existed. |
| `GET /s/:token/status` | JSON `{active}`. The page polls it every 5 s and swaps to "Access ended" in place. |

The filter is enforced on the server: unshared categories are never serialized into the response.

**Wallet** (`src/pass.js`, `passkit-generator`)
- A generic pass with a Consentra logo/colour and a QR containing the share URL.
- Fields: patient name, shared categories, and expiry (also set as `expirationDate`).
- Certificates come from `server/certs/` (`pass.cer` or `.pem`, `pass.key`, `wwdr.pem`). The Team ID and Pass Type ID are read from the certificate subject.
- `scripts/make-pass-csr.sh` creates the key and CSR and prints the portal steps. The WWDR G4 certificate is downloaded automatically.

### 2. iOS app (`ios/`, SwiftUI, iOS 17, XcodeGen)

The design follows Figma file `7nyXa4MTnf1RFKKZ9Xe5Fl`: native iOS grouped lists, SF Symbols, and a Consentra gradient card. The tab bar has **Passport · Health · Share · Activity**.

| Screen | Figma | Behaviour |
|---|---|---|
| Passport Home | 09 | Passport card (name, sources connected, last updated). Stats: records / providers / active access. Quick actions. A "Connect records" CTA when nothing is connected. |
| Connect Records → Sign-In → Authorize → Connected | 22–25 | Pick Thameside General (UK flag) from the list, sign in with a fake prefilled form, see the scopes on the authorize screen, then the success screen calls `/api/source/connect`. |
| My Health | 10 | Categories with counts. Tapping one lists its items. |
| Share | 18 | Toggle categories (all off by default, so the patient opts in). Duration chips: 1 h / 24 h / 7 d / 30 d. Optional label ("Dr. at Mass General"). The Create button is disabled until at least one category is picked. |
| Present to Provider | 19 | Large QR, expiry countdown, "Add to Apple Wallet" button (`PKAddPassesViewController`, shown only if `walletAvailable`), and a Share link button. |
| Access Management → Detail → Revoke | 15–17 | Shares grouped as Active / Ended. Detail shows categories, expiry and view log. Revoke asks for confirmation, then calls the API. |
| Activity | 26 | Flat timeline of share created / viewed / revoked events. |
| Settings | 27 (sheet from the avatar) | Server base URL. |

Server state is fetched on appear and on pull-to-refresh; nothing is stored in the app beyond the base URL.

## Constraints

- Xcode 15.4, iOS 17 SDK, Swift 5.10. No third-party Swift packages.
- Must be demoable within about an hour. The order of build is: server and clinician page → app share flow → Wallet → polish.
- With no certificate present, everything except the Wallet button still works.

## Left to the builder

Visual details within the Figma style, copy, exact fake record contents (clinically plausible and fictional), file layout inside each part, and error states beyond "server unreachable".

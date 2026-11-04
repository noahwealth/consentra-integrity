# Running Consentra locally

This guide gets a new developer from a fresh clone to a working demo on their MacBook, in about 10 minutes. For *why* things are built this way, see [`decision.md`](../decision.md).

## 1. Prerequisites

| Tool | Version | Install |
|---|---|---|
| macOS + Xcode | Xcode 15.4 or newer, with an iOS 17+ simulator | App Store |
| Node.js | 20 or newer (22+ recommended) | `brew install node` or nvm |
| XcodeGen | recent | `brew install xcodegen` |

You don't need an Apple Developer account to run in the simulator.

## 2. Run the server

```bash
git clone https://github.com/noahwealth/consentra-integrity.git
cd consentra/server
npm install
npm start
```

It prints something like:

```
Consentra server on :3000
Share links will use http://192.168.1.23:3000
```

- **Data:** a single fictional patient (Noah Dixon) from a fictional London hospital. State is saved to `server/data/state.json` (gitignored).
- **Port:** to use a different port, run `PORT=4000 npm start` and update the server URL in the app's Settings to match.

## 3. Run the iOS app

```bash
cd ios
xcodegen            # generates Consentra.xcodeproj (gitignored, so re-run after pulling changes to project.yml)
open Consentra.xcodeproj
```

Pick any iPhone simulator and press **Run**. The app talks to `http://localhost:3000` by default. You can change this under the **ND avatar → Settings**.

Then follow the 6-step demo script in the [README](../README.md#demo-script-about-3-minutes).

## 4. Apple Wallet: do I need a certificate?

**No, not to develop.** Without signing certificates, everything works except the **Add to Apple Wallet** button, which is hidden automatically. The QR code, the clinician page, sharing, expiry and revoke all work.

If you're working on the Wallet pass itself, get the team's existing signing files. **Don't create your own.** **Ask Ali** for these three files. Ali will hand them over directly (AirDrop in person is best):

```
server/certs/pass.pem    # Pass Type ID certificate (pass.com.aliabdullah.consentra)
server/certs/pass.key    # its private key (SECRET)
server/certs/wwdr.pem    # Apple's WWDR G4 intermediate (public)
```

Drop them into `server/certs/` and restart the server. You can confirm with `cd server && npm test`: the `certInfo reads ids from cert` and `pkpass is a zip with signature` tests now run instead of skipping.

Rules for these files:
- `server/certs/*` is gitignored. **Never commit them, and never send `pass.key` over Slack, email or tickets.**
- If the private key leaks, revoke the certificate in the Apple Developer portal (Certificates → Pass Type ID). Then create a new one with `scripts/make-pass-csr.sh` and redistribute it.

Why the team shares one certificate is explained in [decision.md D11](../decision.md).

## 5. Run on a real iPhone (optional)

1. Make sure the Mac and iPhone are on the **same Wi-Fi**. Check by opening `http://<your-mac-ip>:3000/api/record` in the phone's Safari; you should see some JSON.
   - Office and guest networks often block devices from talking to each other. If that page doesn't load, use your phone's hotspot or a home network.
2. On the iPhone, turn on Developer Mode (Settings → Privacy & Security → Developer Mode), then connect it to the Mac by cable and tap Trust.
3. **Signing:** the project signs with team `YRL45Q79LJ`. Either ask to be added to that Apple Developer team, or select your own team under Xcode → Consentra target → Signing & Capabilities. That change is lost when you re-run `xcodegen`, so don't commit it.
4. Run on the device. Then in the app, go to Settings, enter the URL the server printed (e.g. `http://192.168.1.23:3000`), and tap **Save & test connection**. Allow the Local Network prompt.
5. **Xcode version:** Xcode can only install on iOS versions it knows about. If your iPhone's iOS is newer than your Xcode supports, update Xcode.

You can test the **clinician view** from any browser on the same network. Scan the QR, or open the share link. On the Mac itself, `http://localhost:3000/s/<token>` works too.

## 6. Tests

```bash
cd server && npm test     # API, clinician filtering, expiry/revoke, pass signing (signing tests skip without certs)

cd ios && xcodebuild test -scheme Consentra \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:ConsentraTests                     # unit tests, no server needed
```

`ConsentraUITests` drives the whole demo in the simulator. Before running it:
- **It needs a running server with fresh data, and it changes that data.** Don't run it against a server you're about to demo from. Reset afterwards (see below).
- `testRevokeFromManageAccess` also needs something opening the share link, playing the clinician. The easiest way is to open the link in a browser while the test runs.
- Set `TEST_RUNNER_SCREENSHOT_DIR=/some/dir` to save a screenshot of each step.

## 7. Reset the demo data

```bash
lsof -ti tcp:3000 | xargs kill; rm -f server/data/state.json; (cd server && npm start)
```

The app shows "Connect your records" again on the next refresh. Pull down to refresh.

## 8. Where things live

```
server/
  index.js                 # starts the server on 0.0.0.0:$PORT
  src/app.js               # routes: patient API (/api/*) and clinician page (/s/:token)
  src/store.js             # share store (JSON file), expiry/revoke status
  src/clinician.js         # the clinician's read-only HTML page
  src/pass.js              # Apple Wallet pass building and signing
  src/source/thameside.js  # the fake hospital's FHIR-shaped data
  src/units.js             # UK → US lab unit conversions
  pass-model/              # pass.json and images (re-generate with scripts/make-pass-icons.mjs)
ios/
  project.yml              # XcodeGen spec, the source of truth for the Xcode project
  Consentra/               # SwiftUI app: AppModel, API, Models, Views/
  ConsentraTests/          # unit tests
  ConsentraUITests/        # end-to-end demo flow
scripts/                   # CSR/cert setup, icon generation
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| App shows "Can't reach the Consentra server at …" | Start the server, and check the URL in Settings. A real iPhone needs the Mac's IP, not `localhost`. |
| Phone can't open the share link / QR | It's not on the same network, or the network blocks devices from talking to each other. Try a hotspot. |
| No "Add to Apple Wallet" button | There are no certificates in `server/certs/`. That's expected; see section 4. |
| `EADDRINUSE :3000` | A server is already running. Use `lsof -ti tcp:3000 \| xargs kill`, or run on another port with `PORT=4000`. |
| Xcode says the project is "in a future project file format" | Your XcodeGen is too old to honour `projectFormat` in `project.yml`. Run `brew upgrade xcodegen`. |
| Wrong IP in share links (VPN, Ethernet) | The server picks the first network interface it finds (`en0` first). Disconnect the VPN, or restart the server on the network you want. |
| Signing error on device | Select your team in Signing & Capabilities (section 5, step 3). |

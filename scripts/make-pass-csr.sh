#!/usr/bin/env bash
# Generates the private key + CSR for an Apple Pass Type ID certificate (see decision.md D4),
# and fetches Apple's WWDR G4 intermediate. The key stays in server/certs/ (gitignored).
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/server/certs"
mkdir -p "$DIR"
if [[ -f "$DIR/pass.key" ]]; then
  echo "pass.key already exists — refusing to overwrite (delete it to start over)."; exit 1
fi
openssl genrsa -out "$DIR/pass.key" 2048
chmod 600 "$DIR/pass.key"
openssl req -new -key "$DIR/pass.key" -out "$DIR/pass.csr" -subj "/CN=Consentra Pass Signing/C=US"
curl -fsSL -o "$DIR/wwdr.cer" https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer
openssl x509 -inform DER -in "$DIR/wwdr.cer" -out "$DIR/wwdr.pem"
echo "Created: $DIR/pass.key (secret), $DIR/pass.csr (upload this), $DIR/wwdr.pem"

#!/usr/bin/env bash
#
# Creates a self-signed code-signing certificate so development builds keep a
# stable signature.
#
# Why this exists
# ---------------
# macOS binds Screen & System Audio Recording (and the other privacy
# permissions) to an app's *code signature*, not to its path or bundle
# identifier. An ad hoc signature is derived from the binary, so it changes on
# every build and every build looks like a different app to TCC: System Settings
# still shows Snaplet switched on, while Snaplet still says the permission is
# missing.
#
# Signing with a certificate instead binds the grant to the certificate, which
# does not change when the code does. Grant the permission once and it survives
# every rebuild.
#
# This certificate is only good on this Mac. It is not a Developer ID, it does
# not let anyone else run the app, and it is not a substitute for notarisation.
#
# Run it yourself — it writes to your login keychain and macOS will ask for your
# password.
#
set -euo pipefail

NAME="${1:-Snaplet Dev}"
DAYS=3650

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$NAME"; then
  echo "\"$NAME\" already exists in your keychain. Nothing to do."
  echo
  echo "Build with it:"
  echo "  SIGN_IDENTITY=\"$NAME\" ./scripts/build-release.sh"
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[ dn ]
CN = $NAME

[ v3 ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CONF

echo "Generating a self-signed code-signing certificate for \"$NAME\"…"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days "$DAYS" -config "$WORK/openssl.cnf" >/dev/null 2>&1

# macOS refuses a PKCS#12 bundle with an empty passphrase, so give it a
# throwaway one. It lives only in this script's temporary directory.
P12_PASS=$(openssl rand -hex 16)
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$P12_PASS" -name "$NAME" >/dev/null 2>&1

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
[ -f "$KEYCHAIN" ] || KEYCHAIN="$HOME/Library/Keychains/login.keychain"

echo "Importing into your login keychain (macOS will ask for your password)…"
# -T lets codesign use the key without prompting on every build.
security import "$WORK/identity.p12" \
  -k "$KEYCHAIN" -P "$P12_PASS" -f pkcs12 \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "Marking the certificate as trusted for code signing…"
# User trust domain only — this does not touch the system trust store. Signing
# works without it; trust is what makes the identity show up under
# "find-identity -v", which is how everyone checks.
TRUSTED=yes
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" \
  || TRUSTED=no

# Lets codesign use the key without a prompt on every build. This asks for your
# login keychain password; skipping it only means macOS will ask for permission
# the first time you build, where "Always Allow" has the same effect.
echo "Allowing codesign to use the key (asks for your login keychain password)."
echo "You can press Ctrl-C here and click \"Always Allow\" at the first build instead."
security set-key-partition-list -S apple-tool:,apple:,codesign: "$KEYCHAIN" >/dev/null 2>&1 \
  || echo "  Skipped — expect an \"Always Allow\" prompt on the first build."

echo
if security find-identity -v -p codesigning | grep -qF "$NAME"; then
  echo "Done. \"$NAME\" is ready:"
  security find-identity -v -p codesigning | grep -F "$NAME" | sed 's/^/  /'
elif security find-identity -p codesigning | grep -qF "$NAME"; then
  echo "\"$NAME\" is in your keychain and codesign can use it, but macOS does"
  echo "not list it as trusted, so \"find-identity -v\" will not show it."
  echo "Builds will still work. To clear the warning, open Keychain Access, find"
  echo "\"$NAME\", and set Code Signing trust to \"Always Trust\"."
  [ "$TRUSTED" = "no" ] && echo "(The trust step was declined or failed.)"
else
  echo "The certificate was imported but no matching identity was found." >&2
  echo "The private key probably did not import. Try again, or create the" >&2
  echo "certificate by hand: Keychain Access > Certificate Assistant >" >&2
  echo "Create a Certificate, Self Signed Root, Code Signing." >&2
  exit 1
fi

echo
echo "Build with it:"
echo "  SIGN_IDENTITY=\"$NAME\" ./scripts/build-release.sh"
echo
echo "Then grant Screen & System Audio Recording once. It will survive rebuilds."
echo
echo "If a stale entry gets in the way first:"
echo "  tccutil reset ScreenCapture app.snaplet.Snaplet"

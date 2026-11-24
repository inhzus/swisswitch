#!/bin/sh
# One-time setup: creates a self-signed "swisswitch Dev" code-signing identity in
# the login keychain. Signing with it (scripts/bundle.sh does so automatically)
# gives the app a designated requirement of "this bundle ID + this certificate"
# instead of a per-build hash, so the Accessibility grant survives rebuilds.
set -e
NAME="swisswitch Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists"; exit 0
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/req.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/req.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -passout pass:swisswitch -out "$TMP/id.p12"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P swisswitch -T /usr/bin/codesign
echo "Created \"$NAME\". Rebuild with scripts/bundle.sh, then grant Accessibility once more."

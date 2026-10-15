#!/bin/zsh
# make-signing-identity.sh - optional, one-time: create the self-signed code-signing
# identity "Replicat Local Signing" in the login keychain. A stable signature lets
# macOS keep Replicat's Accessibility permission across rebuilds. Nothing leaves
# this Mac; the key is usable only by /usr/bin/codesign.
set -euo pipefail
NAME="Replicat Local Signing"
security find-certificate -c "$NAME" >/dev/null 2>&1 && { print "already exists"; exit 0; }
T=$(mktemp -d); trap 'rm -rf $T' EXIT
cat > $T/cfg <<CFG
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout $T/key.pem -out $T/cert.pem -config $T/cfg 2>/dev/null
openssl pkcs12 -export -legacy -inkey $T/key.pem -in $T/cert.pem -out $T/id.p12 -passout pass:replicat 2>/dev/null \
  || openssl pkcs12 -export -inkey $T/key.pem -in $T/cert.pem -out $T/id.p12 -passout pass:replicat
security import $T/id.p12 -k ~/Library/Keychains/login.keychain-db -P replicat -T /usr/bin/codesign
print "created $NAME"

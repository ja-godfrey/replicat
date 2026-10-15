#!/bin/zsh
# build.sh - compile Replicat and install it to ~/Applications/Replicat.app.
#
#   ./build.sh                 build, sign, install
#   ./build.sh --no-install    build into ./build/Replicat.app only
#
# Signing: if a code-signing identity named "Replicat Local Signing" exists (make
# one with ./make-signing-identity.sh), the app is signed with it, and macOS keeps
# the Accessibility permission across rebuilds. Otherwise it is signed ad hoc,
# which works the same but asks you to re-enable Accessibility after each rebuild.
# Override the identity with REPLICAT_SIGN_IDENTITY="Name".
set -euo pipefail
cd "${0:a:h}"
IDENTITY=${REPLICAT_SIGN_IDENTITY:-Replicat Local Signing}
OUT=build/Replicat.app
mkdir -p build
swiftc -O -o build/Replicat src/main.swift
rm -rf "$OUT"; mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp Info.plist "$OUT/Contents/"
cp build/Replicat "$OUT/Contents/MacOS/"
[[ -f assets/AppIcon.icns ]] && cp assets/AppIcon.icns "$OUT/Contents/Resources/"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" --identifier io.github.ja-godfrey.replicat "$OUT"
else
  codesign --force --sign - --identifier io.github.ja-godfrey.replicat "$OUT"
  print "note: signed ad hoc (no \"$IDENTITY\" identity); re-enable Accessibility after rebuilding"
fi
[[ ${1:-} == --no-install ]] && { print "built $OUT"; exit 0; }
APP=$HOME/Applications/Replicat.app
mkdir -p "$HOME/Applications"
pkill -x Replicat 2>/dev/null && sleep 0.5 || true
rm -rf "$APP"; cp -R "$OUT" "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
print "installed $APP"

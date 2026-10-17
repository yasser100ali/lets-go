#!/bin/bash
# Recreate the dedicated signing keychain from ~/.appstoreconnect/letsgo-signing/
# (dist.p12, p12_password, keychain_password, profile.mobileprovision).
# Run once on a new Mac; ship.sh then signs without any keychain prompt.
set -euo pipefail
SIGN="$HOME/.appstoreconnect/letsgo-signing"
KC="$HOME/Library/Keychains/letsgo-signing.keychain-db"
KCPW=$(cat "$SIGN/keychain_password")
[ -f "$KC" ] || security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$KCPW" "$KC"
security import "$SIGN/dist.p12" -k "$KC" -P "$(cat "$SIGN/p12_password")" -T /usr/bin/codesign -T /usr/bin/security || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null
LIST=$(security list-keychains -d user | tr -d '"' | xargs)
case "$LIST" in *letsgo-signing*) ;; *) security list-keychains -d user -s $LIST "$KC" ;; esac
UUID=$(security cms -D -i "$SIGN/profile.mobileprovision" | plutil -extract UUID raw -)
mkdir -p "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
cp "$SIGN/profile.mobileprovision" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$UUID.mobileprovision"
security find-identity -v -p codesigning "$KC"

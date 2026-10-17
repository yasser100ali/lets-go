#!/bin/bash
# Bump the build number, archive Release, upload to TestFlight.
# Signing is automatic: xcodebuild uses the App Store Connect API key to fetch
# or create the App Store profile, so no Xcode account login is needed.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_JSON="$HOME/.appstoreconnect/letsgo_asc_api_key.json"
KEY_ID=$(python3 -c "import json;print(json.load(open('$KEY_JSON'))['key_id'])")
ISSUER=$(python3 -c "import json;print(json.load(open('$KEY_JSON'))['issuer_id'])")
KEY_P8="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_P8" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")

python3 scripts/asc.py app >/dev/null || { echo "Create the app in App Store Connect first (bundle id com.yasser100ali.letsgo)."; exit 1; }

if [ "${SKIP_BUMP:-0}" != "1" ]; then scripts/bump-build.sh; fi
BUILD=$(sed -n 's/^CURRENT_PROJECT_VERSION = //p' ios/Config.xcconfig)
OUT="build/$BUILD"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "Archiving build $BUILD"
xcodebuild archive -project ios/LetsGo.xcodeproj -scheme LetsGo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/LetsGo.xcarchive" "${AUTH[@]}" -quiet

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>X3HMA23KKN</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>testFlightInternalTestingOnly</key><true/>
</dict></plist>
PLIST

echo "Uploading build $BUILD to App Store Connect"
xcodebuild -exportArchive -archivePath "$OUT/LetsGo.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" "${AUTH[@]}"
echo "Uploaded build $BUILD. It shows up in TestFlight after Apple finishes processing (usually 5-15 min)."

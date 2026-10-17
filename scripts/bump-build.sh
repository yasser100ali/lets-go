#!/bin/bash
# CURRENT_PROJECT_VERSION += 1 in ios/Config.xcconfig.
set -euo pipefail
cd "$(dirname "$0")/.."
cur=$(sed -n 's/^CURRENT_PROJECT_VERSION = //p' ios/Config.xcconfig)
next=$((cur + 1))
sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $next/" ios/Config.xcconfig
echo "Build $cur -> $next"

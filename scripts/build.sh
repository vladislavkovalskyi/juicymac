#!/bin/zsh
# Builds Juicy Mac. Usage: scripts/build.sh [Debug|Release]
set -e
config=${1:-Debug}
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

command -v xcodegen >/dev/null || { echo "XcodeGen is missing: brew install xcodegen"; exit 1; }
xcodegen generate
xcodebuild -project JuicyMac.xcodeproj -scheme JuicyMac -sdk macosx \
  -configuration "$config" -derivedDataPath build build
echo "Built: build/Build/Products/$config/Juicy Mac.app"

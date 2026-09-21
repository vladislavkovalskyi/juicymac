#!/bin/zsh
# Runs the JuicyKit test suite (pure logic plus live samplers on this Mac).
set -e
cd "$(dirname "$0")/../JuicyKit"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export SDKROOT=${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}
swift test

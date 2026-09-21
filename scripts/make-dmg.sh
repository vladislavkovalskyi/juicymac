#!/bin/zsh
# Builds a Release app and packs it into a DMG. Usage: scripts/make-dmg.sh [version]
set -e
cd "$(dirname "$0")/.."
version=${1:-$(grep -m1 'MARKETING_VERSION' project.yml | tr -dc '0-9.')}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

./scripts/build.sh Release
app="build/Build/Products/Release/Juicy Mac.app"
[[ -d "$app" ]] || { echo "Release build not found"; exit 1; }

stage=$(mktemp -d)/JuicyMac
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"

# Volume icon, so the mounted disk shows the juice glass.
icons=$(mktemp -d)/icon.iconset
mkdir -p "$icons"
src="App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$src" --out "$icons/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) "$src" --out "$icons/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icons" -o "$stage/.VolumeIcon.icns"
SetFile -a C "$stage" 2>/dev/null || true

mkdir -p dist
out="dist/JuicyMac-$version.dmg"
rm -f "$out"
hdiutil create -volname "Juicy Mac" -srcfolder "$stage" -ov -format UDZO "$out" >/dev/null
echo "$out"
shasum -a 256 "$out"

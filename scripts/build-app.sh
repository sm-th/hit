#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
version="${1:?Usage: bash scripts/build-app.sh X.Y.Z}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must use X.Y.Z format" >&2
  exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=13.0
swift build --configuration release --arch arm64 --arch x86_64
bin_dir="$(swift build --configuration release --arch arm64 --arch x86_64 --show-bin-path)"
output="$PWD/dist"
app="$output/Hit.app"
if [[ -e "$app" ]]; then
  echo "dist/Hit.app already exists; move the previous build aside first." >&2
  exit 1
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Hit" "$app/Contents/MacOS/Hit"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$output/Hit.iconset"
iconutil -c icns "$output/Hit.iconset" -o "$app/Contents/Resources/Hit.icns"
cp LICENSE "$app/Contents/Resources/LICENSE"
lipo "$app/Contents/MacOS/Hit" -verify_arch arm64 x86_64
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"
name="Hit-$version-universal"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$name.zip"
staging="$(mktemp -d "${TMPDIR:-/tmp}/hit-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Hit.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Hit $version" -srcfolder "$staging" -ov -format UDZO "$output/$name.dmg"
(cd "$output" && shasum -a 256 "$name.dmg" "$name.zip" > SHA256SUMS)
printf 'Packaged Hit %s in %s\n' "$version" "$output"

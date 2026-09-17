#!/usr/bin/env bash
# Builds a Release "Black Hole.app" and packages it into dist/BlackHole-<version>.dmg.
#
# Without signing credentials the app is ad-hoc signed, which is fine for local use and for
# open-source downloads (users approve it once in System Settings). To produce a notarized build set:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="<keychain profile created with `xcrun notarytool store-credentials`>"
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)}"
APP_NAME="Black Hole"
DERIVED="build/release"
APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
STAGE="build/dmg-stage"
DMG="dist/BlackHole-$VERSION.dmg"

echo "==> Generating project"
xcodegen generate --quiet

echo "==> Building $APP_NAME $VERSION (Release, arm64)"
xcodebuild -project BlackHole.xcodeproj -scheme BlackHole -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MARKETING_VERSION="$VERSION" build -quiet

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "==> Signing with $DEVELOPER_ID"
  codesign --force --deep --options runtime --timestamp \
    --entitlements BlackHole/Support/BlackHole.entitlements \
    --sign "$DEVELOPER_ID" "$APP"
fi

echo "==> Packaging $DMG"
rm -rf "$STAGE" && mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarizing"
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "==> Done: $DMG"

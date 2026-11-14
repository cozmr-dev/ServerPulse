#!/bin/zsh
# Baut ServerPulse als Universal-App (Apple Silicon + Intel).
#
#   ./build.sh          → build/ServerPulse.app
#   ./build.sh dmg      → zusätzlich build/ServerPulse-<Version>.dmg und .sha256
#
# Optional:
#   VERSION=1.2.0 ./build.sh dmg   Version überschreiben (Standard: Resources/Info.plist)
#   ARCHS="arm64" ./build.sh       nur eine Architektur bauen (schneller beim Entwickeln)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ServerPulse"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
SOURCE_PLIST="Resources/Info.plist"
PLISTBUDDY="/usr/libexec/PlistBuddy"

VERSION="${VERSION:-$($PLISTBUDDY -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST")}"
VERSION="${VERSION#v}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# Jede Architektur in einem eigenen Build-Ordner bauen und danach mit lipo zusammenführen.
SLICES=()
for arch in ${=ARCHS:-arm64 x86_64}; do
    echo "▶︎ Kompiliere ${APP_NAME} ${VERSION} für ${arch} …"
    TRIPLE="${arch}-apple-macosx14.0"
    swift build -c release --triple "$TRIPLE" --scratch-path ".build/${arch}"
    SLICES+=("$(swift build -c release --triple "$TRIPLE" --scratch-path ".build/${arch}" --show-bin-path)/${APP_NAME}")
done

echo "▶︎ Erzeuge ${APP_DIR} …"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
lipo -create "${SLICES[@]}" -output "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "$SOURCE_PLIST" "${APP_DIR}/Contents/Info.plist"
cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
for lproj in Resources/*.lproj; do
    cp -R "$lproj" "${APP_DIR}/Contents/Resources/"
done
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"
$PLISTBUDDY -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_DIR}/Contents/Info.plist"
$PLISTBUDDY -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_DIR}/Contents/Info.plist"

echo "▶︎ Ad-hoc-Signatur …"
codesign --force --sign - --timestamp=none "$APP_DIR"
echo "   Architekturen: $(lipo -archs "${APP_DIR}/Contents/MacOS/${APP_NAME}")"

if [[ "${1:-}" == "dmg" ]]; then
    DMG_NAME="${APP_NAME}-${VERSION}.dmg"
    DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
    STAGING="$(mktemp -d)"
    trap 'rm -rf "$STAGING"' EXIT

    echo "▶︎ Erzeuge ${DMG_PATH} …"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    rm -f "$DMG_PATH"
    if diskutil image create from --help >/dev/null 2>&1; then
        # macOS 26+: hdiutil create ist veraltet.
        if ! diskutil image create from --format UDZO --volumeName "${APP_NAME} ${VERSION}" \
            "$STAGING" "$DMG_PATH" >"${STAGING}.log" 2>&1; then
            cat "${STAGING}.log" >&2
            exit 1
        fi
        rm -f "${STAGING}.log"
    else
        hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGING" \
            -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG_PATH" >/dev/null
    fi
    (cd "$BUILD_DIR" && shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256")
    echo "   SHA-256: $(cut -d' ' -f1 "${DMG_PATH}.sha256")"
    echo "✅ Fertig: $(pwd)/${DMG_PATH}"
else
    echo "✅ Fertig: $(pwd)/${APP_DIR}"
    echo "   Starten mit: open \"${APP_DIR}\""
fi

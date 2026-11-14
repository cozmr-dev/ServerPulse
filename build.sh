#!/bin/zsh
# Baut ServerPulse im Release-Modus und erzeugt build/ServerPulse.app
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="ServerPulse"
APP_DIR="build/${APP_NAME}.app"

echo "▶︎ Kompiliere (release) …"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▶︎ Erzeuge ${APP_DIR} …"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "▶︎ Ad-hoc-Signatur …"
codesign --force --deep --sign - "${APP_DIR}"

echo "✅ Fertig: $(pwd)/${APP_DIR}"
echo "   Starten mit: open \"${APP_DIR}\""

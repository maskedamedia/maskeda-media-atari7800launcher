#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Atari7800Launcher"
EXECUTABLE_NAME="Atari7800Launcher"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
INFO_PLIST_SOURCE="${ROOT_DIR}/Resources/AppBundle/Info.plist"
APP_ICON_SOURCE="${ROOT_DIR}/Resources/AppBundle/AppIcon.png"
ICONSET_DIR="${DIST_DIR}/AppIcon.iconset"
ICON_FILE="${RESOURCES_DIR}/AppIcon.icns"
BUILD_TIMESTAMP="$(date '+%Y%m%d%H%M%S')"

mkdir -p "${DIST_DIR}"

swift build -c "${BUILD_CONFIG}" --package-path "${ROOT_DIR}"
BIN_DIR="$(swift build -c "${BUILD_CONFIG}" --package-path "${ROOT_DIR}" --show-bin-path)"
BINARY_PATH="${BIN_DIR}/${EXECUTABLE_NAME}"

if [[ ! -x "${BINARY_PATH}" ]]; then
  echo "error: built executable not found at ${BINARY_PATH}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${INFO_PLIST_SOURCE}" "${CONTENTS_DIR}/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_TIMESTAMP}" "${CONTENTS_DIR}/Info.plist"
plutil -replace CFBundleShortVersionString -string "${BUILD_TIMESTAMP}" "${CONTENTS_DIR}/Info.plist"
cp "${BINARY_PATH}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
cp "${ROOT_DIR}/README.md" "${RESOURCES_DIR}/README.md"
cp "${ROOT_DIR}/Docs/THIRD_PARTY_NOTICES.md" "${RESOURCES_DIR}/THIRD_PARTY_NOTICES.md"

if [[ -f "${APP_ICON_SOURCE}" ]]; then
  rm -rf "${ICONSET_DIR}"
  mkdir -p "${ICONSET_DIR}"
  sips -z 16 16 "${APP_ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${APP_ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${APP_ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${APP_ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${APP_ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${APP_ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${APP_ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${APP_ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "${APP_ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
  cp "${APP_ICON_SOURCE}" "${ICONSET_DIR}/icon_512x512@2x.png"
  iconutil -c icns "${ICONSET_DIR}" -o "${ICON_FILE}"
fi

/usr/bin/zip -qry "${DIST_DIR}/${APP_NAME}.zip" "${APP_DIR}"

echo "app bundle: ${APP_DIR}"
echo "zip archive: ${DIST_DIR}/${APP_NAME}.zip"
echo "bundle version: ${BUILD_TIMESTAMP}"

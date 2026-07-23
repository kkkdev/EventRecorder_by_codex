#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="EventRecorder"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-io.github.eventrecorder.EventRecorder}"
BUILD_DIR="${ROOT_DIR}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun が見つかりません。Xcode Command Line Tools をインストールしてください。" >&2
  exit 1
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
if [[ -z "${SDK_PATH}" ]]; then
  echo "error: macOS SDK が見つかりません。" >&2
  exit 1
fi

ARCH="$(uname -m)"
case "${ARCH}" in
  arm64)
    TARGET="arm64-apple-macos13.0"
    ;;
  x86_64)
    TARGET="x86_64-apple-macos13.0"
    ;;
  *)
    echo "error: 未対応アーキテクチャです: ${ARCH}" >&2
    exit 1
    ;;
esac

SWIFT_SOURCES=()
while IFS= read -r source_file; do
  SWIFT_SOURCES+=("${source_file}")
done < <(find "${ROOT_DIR}/EventRecorder" -type f -name '*.swift' | sort)
if [[ ${#SWIFT_SOURCES[@]} -eq 0 ]]; then
  echo "error: Swiftソースが見つかりません。" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
cp "${ROOT_DIR}/EventRecorder/Info.plist" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_IDENTIFIER}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}" "${CONTENTS_DIR}/Info.plist"

swiftc \
  -sdk "${SDK_PATH}" \
  -target "${TARGET}" \
  -module-name "${APP_NAME}" \
  "${SWIFT_SOURCES[@]}" \
  -o "${MACOS_DIR}/${APP_NAME}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Foundation \
  -framework Combine \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework CoreMedia \
  -framework ScreenCaptureKit \
  -framework ImageIO \
  -framework UniformTypeIdentifiers \
  -framework CoreImage \
  -framework WebKit \
  -framework UserNotifications

if command -v codesign >/dev/null 2>&1; then
  # ad-hoc署名でも designated requirement を identifier 固定にして、
  # ビルド毎のcdhash変化で別アプリ扱いになる問題を避ける。
  codesign \
    --force \
    --deep \
    --sign - \
    --timestamp=none \
    --identifier "${BUNDLE_IDENTIFIER}" \
    -r="designated => identifier \"${BUNDLE_IDENTIFIER}\"" \
    "${APP_DIR}" >/dev/null 2>&1 || true
fi

echo "Built: ${APP_DIR}"

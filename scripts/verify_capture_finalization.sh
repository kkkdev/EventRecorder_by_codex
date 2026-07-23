#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/event-recorder-verify.XXXXXX")"
VERIFY_BINARY="${VERIFY_DIR}/verify_capture_finalization"

cleanup() {
  rm -rf "${VERIFY_DIR}"
}
trap cleanup EXIT

case "$(uname -m)" in
  arm64)
    TARGET="arm64-apple-macos13.0"
    ;;
  x86_64)
    TARGET="x86_64-apple-macos13.0"
    ;;
  *)
    echo "error: 未対応アーキテクチャです: $(uname -m)" >&2
    exit 1
    ;;
esac

swiftc \
  -sdk "${SDK_PATH}" \
  -target "${TARGET}" \
  -module-name EventRecorderVerification \
  "${ROOT_DIR}/EventRecorder/Domain/AudioDiagnostics.swift" \
  "${ROOT_DIR}/EventRecorder/Domain/CaptureTarget.swift" \
  "${ROOT_DIR}/EventRecorder/Domain/CaptureManifest.swift" \
  "${ROOT_DIR}/EventRecorder/Domain/CaptureFinalization.swift" \
  "${ROOT_DIR}/EventRecorder/Domain/CaptureState.swift" \
  "${ROOT_DIR}/EventRecorder/Domain/VideoSampleBufferPolicy.swift" \
  "${ROOT_DIR}/scripts/verify_capture_finalization.swift" \
  -o "${VERIFY_BINARY}"

"${VERIFY_BINARY}"

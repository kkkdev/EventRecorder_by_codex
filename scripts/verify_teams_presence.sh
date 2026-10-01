#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/event-recorder-teams-verify.XXXXXX")"
VERIFY_BINARY="${VERIFY_DIR}/verify_teams_presence"

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
  -module-name EventRecorderTeamsVerification \
  "${ROOT_DIR}/EventRecorder/Domain/TeamsMeetingPresence.swift" \
  "${ROOT_DIR}/scripts/verify_teams_presence.swift" \
  -o "${VERIFY_BINARY}"

"${VERIFY_BINARY}"

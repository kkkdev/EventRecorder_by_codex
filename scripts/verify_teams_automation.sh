#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/teams-automation-verifier"

mkdir -p "${BUILD_DIR}"
swiftc \
  "${ROOT_DIR}/EventRecorder/Domain/CaptureManifest.swift" \
  "${ROOT_DIR}/EventRecorder/Domain/CaptureTarget.swift" \
  "${ROOT_DIR}/EventRecorder/Domain/AudioDiagnostics.swift" \
  "${ROOT_DIR}/EventRecorder/Domain/TeamsAutomationLifecycle.swift" \
  "${ROOT_DIR}/scripts/verify_teams_automation.swift" \
  -o "${BUILD_DIR}/verify_teams_automation"

"${BUILD_DIR}/verify_teams_automation"

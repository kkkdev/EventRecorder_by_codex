#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <session_dir>" >&2
  exit 1
fi

session_dir="$1"
tmp_audio="${session_dir}/recording_tmp.caf"
final_audio="${session_dir}/recording.mp3"
manifest="${session_dir}/manifest.json"

if [[ ! -d "${session_dir}" ]]; then
  echo "Session directory not found: ${session_dir}" >&2
  exit 1
fi

echo "== Session =="
echo "${session_dir}"
echo

echo "== Files =="
ls -la "${session_dir}" | sed 's/^/  /'
echo

if [[ -f "${manifest}" ]]; then
  echo "== manifest.json (audio fields) =="
  if command -v jq >/dev/null 2>&1; then
    jq '{
      completionStatus,
      audioFileName,
      audioDiagnostics,
      captureDiagnostics,
      startedAt,
      endedAt
    }' "${manifest}"
    manifest_audio_file="$(jq -r '.audioFileName // empty' "${manifest}")"
    if [[ -n "${manifest_audio_file}" ]]; then
      case "${manifest_audio_file}" in
        */*)
          echo "Invalid audioFileName in manifest: path separators are not allowed" >&2
          exit 1
          ;;
        *)
          final_audio="${session_dir}/${manifest_audio_file}"
          ;;
      esac
    fi
  else
    grep -E \
      '"completionStatus"|"audioFileName"|"audioDiagnostics"|"captureDiagnostics"|"startedAt"|"endedAt"' \
      "${manifest}" || true
  fi
  echo
fi

if [[ -f "${tmp_audio}" || -f "${final_audio}" ]]; then
  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ffprobe is required. Install ffmpeg first: brew install ffmpeg" >&2
    exit 1
  fi

  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg is required. Install ffmpeg first: brew install ffmpeg" >&2
    exit 1
  fi
else
  echo "== Audio files =="
  echo "音声ファイルはありません。completionStatus と captureDiagnostics を確認してください。"
  echo
fi

if [[ -f "${tmp_audio}" ]]; then
  echo "== ffprobe: recording_tmp.caf =="
  ffprobe -hide_banner -loglevel error -show_streams -show_format "${tmp_audio}"
  echo
  echo "== volumedetect: recording_tmp.caf =="
  ffmpeg -hide_banner -i "${tmp_audio}" -af volumedetect -f null - 2>&1 \
    | grep -E 'mean_volume|max_volume|n_samples' || true
  echo
fi

if [[ -f "${final_audio}" ]]; then
  echo "== ffprobe: recording.mp3 =="
  ffprobe -hide_banner -loglevel error -show_streams -show_format "${final_audio}"
  echo
  echo "== volumedetect: recording.mp3 =="
  ffmpeg -hide_banner -i "${final_audio}" -af volumedetect -f null - 2>&1 \
    | grep -E 'mean_volume|max_volume|n_samples' || true
fi

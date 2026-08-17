#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$base_dir/webdis.json"
pid_file="$base_dir/webdis.pid"

webdis_bin="$(command -v webdis || true)"
if [[ -z "$webdis_bin" ]]; then
  echo "webdis is not installed. Install it first (for example: sudo apt install webdis)." >&2
  exit 1
fi

mkdir -p "$(dirname "$pid_file")"

if [[ -f "$pid_file" ]] && kill -0 "$(<"$pid_file")" 2>/dev/null; then
  echo "Webdis is already running on 127.0.0.1:7379"
  exit 0
fi

rm -f "$pid_file"
if command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 7379 2>/dev/null; then
  echo "Cannot start Webdis: 127.0.0.1:7379 is already in use by another process." >&2
  exit 1
fi

cd "$base_dir"
"$webdis_bin" "$config_file"

for _ in {1..50}; do
  if [[ -f "$pid_file" ]] && kill -0 "$(<"$pid_file")" 2>/dev/null; then
    echo "Webdis started on 127.0.0.1:7379"
    exit 0
  fi
  sleep 0.1
done

echo "Failed to start Webdis" >&2
exit 1

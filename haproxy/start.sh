#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$base_dir/haproxy.cfg"
config_dir="$base_dir/conf.d"
pid_file="$base_dir/haproxy.pid"
socket_file="$base_dir/haproxy.sock"
log_file="$base_dir/haproxy.log"

haproxy_bin="$(command -v haproxy || true)"
if [[ -z "$haproxy_bin" && -x /usr/sbin/haproxy ]]; then
  haproxy_bin=/usr/sbin/haproxy
fi

if [[ -z "$haproxy_bin" ]]; then
  echo "haproxy is not installed. Install it first (for example: sudo apt install haproxy or sudo dnf install haproxy)." >&2
  exit 1
fi

mkdir -p "$(dirname "$pid_file")"

if [[ -f "$pid_file" ]] && kill -0 "$(<"$pid_file")" 2>/dev/null; then
  echo "HAProxy is already running on [::]:6379"
  exit 0
fi

rm -f "$socket_file"

"$haproxy_bin" -c -f "$config_file" -f "$config_dir"
cd "$base_dir"
nohup "$haproxy_bin" -db -f "$config_file" -f "$config_dir" >>"$log_file" 2>&1 </dev/null &
haproxy_pid=$!
printf '%s\n' "$haproxy_pid" >"$pid_file"

echo "HAProxy started on [::]:6379"

#!/usr/bin/env bash
set -uo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
redis_master_config_file="$base_dir/conf.d/00-redis-master.cfg"
pid_file="$base_dir/haproxy.pid"
socket_file="$base_dir/haproxy.sock"
command_timeout="${STATUS_COMMAND_TIMEOUT:-2}"
overall_status=0

print_status() {
  printf '%-20s %-10s %s\n' "$1" "$2" "$3"
}

if [[ ! "$command_timeout" =~ ^[1-9][0-9]*$ ]]; then
  echo "STATUS_COMMAND_TIMEOUT must be a positive integer." >&2
  exit 2
fi

pid=""
if [[ -f "$pid_file" ]]; then
  pid="$(<"$pid_file")"
fi

printf '%-20s %-10s %s\n' "SERVICE" "STATUS" "DETAILS"

if [[ ! "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
  print_status "HAProxy" "STOPPED" "process is not running"
  exit 1
fi

print_status "HAProxy" "RUNNING" "pid=$pid"

listener_address="$(awk '$1 == "bind" { print $2; exit }' "$redis_master_config_file")"
listener_host="${listener_address%:*}"
listener_port="${listener_address##*:}"
listener_host="${listener_host#[}"
listener_host="${listener_host%]}"
if [[ "$listener_host" == "0.0.0.0" || "$listener_host" == "*" ]]; then
  listener_host="127.0.0.1"
elif [[ "$listener_host" == "::" ]]; then
  listener_host="::1"
fi

if [[ -z "$listener_address" || "$listener_host" == "$listener_port" || ! "$listener_port" =~ ^[0-9]+$ ]]; then
  print_status "HAProxy listener" "UNKNOWN" "cannot read bind address from conf.d/00-redis-master.cfg"
  overall_status=1
elif exec 3<>"/dev/tcp/$listener_host/$listener_port" 2>/dev/null; then
  exec 3<&-
  exec 3>&-
  print_status "HAProxy listener" "LISTENING" "$listener_address"
else
  print_status "HAProxy listener" "UNAVAILABLE" "$listener_address"
  overall_status=1
fi

if ! command -v timeout >/dev/null 2>&1; then
  print_status "HAProxy backends" "UNKNOWN" "timeout is not installed"
  exit 2
fi

if ! command -v nc >/dev/null 2>&1; then
  print_status "HAProxy backends" "UNKNOWN" "nc is not installed"
  exit 2
fi

if [[ ! -S "$socket_file" ]]; then
  print_status "HAProxy backends" "UNKNOWN" "Runtime API socket is unavailable"
  exit 1
fi

backend_rows="$(
  printf 'show stat\n' |
    timeout --foreground "${command_timeout}s" nc -U "$socket_file" 2>/dev/null |
    awk -F, '
      NR == 1 {
        sub(/^# /, "", $1)
        for (i = 1; i <= NF; i++) field[$i] = i
        next
      }
      $field["pxname"] == "redis_master_nodes" && $field["svname"] != "BACKEND" {
        printf "%s\t%s\t%s\t%s\n", \
          $field["svname"], $field["status"], \
          $field["check_status"], $field["lastchg"]
      }
    '
)"

if [[ -z "$backend_rows" ]]; then
  print_status "HAProxy backends" "UNKNOWN" "Runtime API returned no backend status"
  exit 1
fi

server_count=0
up_count=0
while IFS=$'\t' read -r server status check_status last_change; do
  [[ -n "$server" ]] || continue
  ((server_count += 1))
  if [[ "$status" == UP* ]]; then
    ((up_count += 1))
  fi
  print_status "HAProxy/$server" "$status" \
    "check=${check_status:-unknown} last-change=${last_change:-unknown}s"
done <<< "$backend_rows"

if ((server_count == 0 || up_count != 1)); then
  overall_status=1
fi

exit "$overall_status"

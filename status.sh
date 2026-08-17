#!/usr/bin/env bash
set -uo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
haproxy_pid_file="$base_dir/haproxy/haproxy.pid"
haproxy_socket="$base_dir/haproxy/haproxy.sock"
webdis_pid_file="$base_dir/webdis/webdis.pid"
overall_status=0
connect_timeout="${STATUS_CONNECT_TIMEOUT:-1}"
command_timeout="${STATUS_COMMAND_TIMEOUT:-2}"
redis_password="${REDIS_PASSWORD:-zhuyanjun+123}"

run_redis_cli() {
  REDISCLI_AUTH="$redis_password" timeout --foreground "${command_timeout}s" \
    redis-cli -t "$connect_timeout" "$@"
}

print_status() {
  printf '%-16s %-10s %s\n' "$1" "$2" "$3"
}

check_redis_node() {
  local name="$1"
  local port="$2"
  local role

  if ! run_redis_cli -h 127.0.0.1 -p "$port" ping 2>/dev/null | grep -qx PONG; then
    print_status "$name" "STOPPED" "no response on 127.0.0.1:$port"
    overall_status=1
    return
  fi

  role="$(run_redis_cli -h 127.0.0.1 -p "$port" --raw role 2>/dev/null | head -n 1)"
  if [[ -z "$role" ]]; then
    role="unknown"
    overall_status=1
  fi
  print_status "$name" "RUNNING" "role=$role"
}

check_sentinel() {
  local -a master_address=()

  if ! run_redis_cli -h 127.0.0.1 -p 26379 ping 2>/dev/null | grep -qx PONG; then
    print_status "Sentinel" "STOPPED" "no response on 127.0.0.1:26379"
    overall_status=1
    return
  fi

  mapfile -t master_address < <(
    run_redis_cli -h 127.0.0.1 -p 26379 --raw \
      sentinel get-master-addr-by-name mymaster 2>/dev/null
  )
  if [[ ${#master_address[@]} -ge 2 ]]; then
    print_status "Sentinel" "RUNNING" "master=${master_address[0]}:${master_address[1]}"
  else
    print_status "Sentinel" "DEGRADED" "mymaster address is unavailable"
    overall_status=1
  fi
}

check_haproxy() {
  local pid=""
  local role=""

  if [[ -f "$haproxy_pid_file" ]]; then
    pid="$(<"$haproxy_pid_file")"
  fi

  if [[ ! "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
    print_status "HAProxy" "STOPPED" "process is not running"
    overall_status=1
    return
  fi

  role="$(run_redis_cli -h 127.0.0.1 -p 6379 --raw role 2>/dev/null | head -n 1)"
  if [[ "$role" == "master" ]]; then
    print_status "HAProxy" "RUNNING" "pid=$pid backend-role=$role"
  else
    print_status "HAProxy" "DEGRADED" "pid=$pid no available master backend"
    overall_status=1
  fi
}

check_haproxy_backends() {
  local backend_rows=""
  local server status check_status last_change
  local server_count=0
  local up_count=0

  if [[ ! -S "$haproxy_socket" ]]; then
    print_status "HAProxy backends" "UNKNOWN" "Runtime API socket is unavailable; restart HAProxy"
    overall_status=1
    return
  fi

  backend_rows="$(
    printf 'show stat\n' |
      timeout --foreground "${command_timeout}s" nc -U "$haproxy_socket" 2>/dev/null |
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
    overall_status=1
    return
  fi

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
}

check_webdis() {
  local pid=""

  if [[ -f "$webdis_pid_file" ]]; then
    pid="$(<"$webdis_pid_file")"
  fi

  if [[ ! "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
    print_status "Webdis" "STOPPED" "process is not running"
    overall_status=1
    return
  fi

  if timeout --foreground "${command_timeout}s" nc -z 127.0.0.1 7379 2>/dev/null; then
    print_status "Webdis" "RUNNING" "pid=$pid http=127.0.0.1:7379"
  else
    print_status "Webdis" "DEGRADED" "pid=$pid no response on 127.0.0.1:7379"
    overall_status=1
  fi
}

if ! command -v redis-cli >/dev/null 2>&1; then
  echo "redis-cli is not installed or is not in PATH." >&2
  exit 2
fi

if ! command -v timeout >/dev/null 2>&1; then
  echo "timeout is not installed or is not in PATH." >&2
  exit 2
fi

if ! command -v nc >/dev/null 2>&1; then
  echo "nc is not installed or is not in PATH." >&2
  exit 2
fi

printf '%-16s %-10s %s\n' "SERVICE" "STATUS" "DETAILS"
check_redis_node "Redis 6380" 6380
check_redis_node "Redis 6381" 6381
check_sentinel
check_haproxy
check_haproxy_backends
check_webdis

exit "$overall_status"

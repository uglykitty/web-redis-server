#!/usr/bin/env bash
set -euo pipefail

sentinel_host="${SENTINEL_HOST:-127.0.0.1}"
sentinel_port="${SENTINEL_PORT:-26379}"
master_name="${SENTINEL_MASTER_NAME:-mymaster}"
failover_timeout="${FAILOVER_TIMEOUT:-30}"
redis_password="${REDIS_PASSWORD:-zhuyanjun+123}"
connect_timeout="${STATUS_CONNECT_TIMEOUT:-1}"
command_timeout="${STATUS_COMMAND_TIMEOUT:-2}"

run_redis_cli() {
  REDISCLI_AUTH="$redis_password" timeout --foreground "${command_timeout}s" \
    redis-cli -t "$connect_timeout" "$@"
}

get_master_address() {
  local -a address=()

  mapfile -t address < <(
    run_redis_cli -h "$sentinel_host" -p "$sentinel_port" --raw \
      sentinel get-master-addr-by-name "$master_name" 2>/dev/null
  )
  if [[ ${#address[@]} -lt 2 || -z "${address[0]}" || -z "${address[1]}" ]]; then
    return 1
  fi
  printf '%s:%s\n' "${address[0]}" "${address[1]}"
}

for required_command in redis-cli timeout; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "$required_command is not installed or is not in PATH." >&2
    exit 2
  fi
done

if ! [[ "$failover_timeout" =~ ^[1-9][0-9]*$ ]]; then
  echo "FAILOVER_TIMEOUT must be a positive integer." >&2
  exit 2
fi

if ! run_redis_cli -h "$sentinel_host" -p "$sentinel_port" ping 2>/dev/null |
  grep -qx PONG; then
  echo "Sentinel is unavailable at $sentinel_host:$sentinel_port." >&2
  exit 1
fi

old_master="$(get_master_address)" || {
  echo "Sentinel does not know master '$master_name'." >&2
  exit 1
}

echo "Current master: $old_master"
echo "Requesting failover for '$master_name'..."
response="$(
  run_redis_cli -h "$sentinel_host" -p "$sentinel_port" --raw \
    sentinel failover "$master_name" 2>&1
)" || {
  echo "Failed to request failover: $response" >&2
  exit 1
}

if [[ "$response" != "OK" ]]; then
  echo "Sentinel rejected the failover request: $response" >&2
  exit 1
fi

deadline=$((SECONDS + failover_timeout))
while ((SECONDS < deadline)); do
  new_master="$(get_master_address || true)"
  if [[ -n "$new_master" && "$new_master" != "$old_master" ]]; then
    echo "Failover completed. New master: $new_master"
    exit 0
  fi
  sleep 0.5
done

echo "Failover was accepted, but the master did not change within ${failover_timeout}s." >&2
echo "Check Sentinel logs and run ./status.sh for the latest state." >&2
exit 1

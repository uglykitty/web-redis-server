#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
redis_password="${REDIS_PASSWORD:-zhuyanjun+123}"

usage() {
  echo "Usage: $0 {start|stop} <name> <port> [config] [redis-server arguments...]" >&2
  exit 2
}

[[ $# -ge 3 ]] || usage

action="$1"
name="$2"
port="$3"
shift 3

is_running() {
  REDISCLI_AUTH="$redis_password" \
    redis-cli -h 127.0.0.1 -p "$port" ping >/dev/null 2>&1
}

case "$action" in
  start)
    [[ $# -ge 1 ]] || usage
    if is_running; then
      echo "$name is already running on port $port"
      exit 0
    fi

    mkdir -p "$base_dir/node-6380/data" "$base_dir/node-6381/data" \
      "$base_dir/sentinel/data"

    # Redis and Sentinel rewrite their configuration during failover. Keep the
    # tracked configuration as a seed and let the process mutate an ignored
    # runtime copy instead.
    config="$1"
    shift
    if [[ "$config" = /* ]]; then
      config_path="$config"
    else
      config_path="$base_dir/$config"
    fi
    service_dir="$(dirname "$config_path")"
    config_name="$(basename "$config_path")"
    service_name="${config_name%.conf}"
    runtime_config="$service_dir/.runtime.conf"
    if [[ ! -f "$runtime_config" ]]; then
      cp "$config_path" "$runtime_config"
    fi

    cd "$service_dir"
    redis-server ./.runtime.conf \
      --pidfile "$service_dir/$service_name.pid" \
      --logfile "$service_dir/$service_name.log" \
      "$@"

    for _ in {1..50}; do
      if is_running; then
        echo "$name started on port $port"
        exit 0
      fi
      sleep 0.1
    done

    echo "Failed to start $name; check its service directory for the log file." >&2
    exit 1
    ;;
  stop)
    [[ $# -eq 0 ]] || usage
    if ! is_running; then
      echo "$name is not running"
      exit 0
    fi

    REDISCLI_AUTH="$redis_password" \
      redis-cli -h 127.0.0.1 -p "$port" shutdown
    echo "$name stopped"
    ;;
  *)
    usage
    ;;
esac

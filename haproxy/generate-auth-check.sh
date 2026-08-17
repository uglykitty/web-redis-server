#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: generate-auth-check.sh [password]

The password can also be supplied through REDIS_PASSWORD. If neither is
provided, the script reads it interactively and echoes the input.
EOF
  exit 2
}

[[ $# -le 1 ]] || usage

if [[ $# -eq 1 ]]; then
  password="$1"
elif [[ -n "${REDIS_PASSWORD:-}" ]]; then
  password="$REDIS_PASSWORD"
elif [[ -t 0 ]]; then
  read -r -p "Redis password: " password
else
  echo "Redis password is required." >&2
  usage
fi

if [[ -z "$password" ]]; then
  echo "Redis password must not be empty." >&2
  exit 2
fi

to_hex() {
  od -An -v -tx1 | tr -d ' \n'
}

LC_ALL=C
password_length=${#password}
auth_hex="$(
  printf '*2\r\n$4\r\nAUTH\r\n$%d\r\n%s\r\n' \
    "$password_length" "$password" | to_hex
)"

printf '生成的 send-binary 内容：\n%s\n' "$auth_hex"

cat >&2 <<'EOF'

替换方法：
1. 打开当前目录下的 conf.d/00-redis-master.cfg。
2. 找到 backend redis_master_nodes 配置段。
3. 找到 AUTH 对应的 tcp-check send-binary 配置行。
4. 只替换 send-binary 后面的十六进制内容，保留 tcp-check send-binary 不变。
5. 不需要修改下一行 tcp-check expect string +OK。
6. 保存配置，然后执行 ./stop.sh && ./start.sh 使配置生效。
EOF

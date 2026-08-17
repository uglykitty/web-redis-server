# HAProxy Redis Master 代理

该目录可以从主项目中单独复制和部署。HAProxy 在固定地址上接收 Redis 客户端连接，
定期检查各 Redis 节点的复制角色，并只把新连接转发给当前 Master。

HAProxy 只负责识别和转发到 Master，不负责将 Replica 提升为 Master。Redis 主从切换仍需
由 Sentinel、Redis Cluster 或其他高可用组件完成。Master 切换会断开已有连接，客户端需要
实现断线重连和必要的命令重试。

## 文件说明

```text
haproxy/
├── README.md
├── haproxy.cfg             # HAProxy 全局配置和代理默认值
├── conf.d/
│   └── 00-redis-master.cfg # Redis Master frontend、backend 和健康检查
├── generate-auth-check.sh  # 生成 AUTH 健康检查所需的十六进制内容
├── start.sh                # 校验配置并启动 HAProxy
├── stop.sh                 # 停止 HAProxy
└── status.sh               # 查看 HAProxy 进程、监听端口和 backend 状态
```

运行后还会在当前目录生成 `haproxy.log`、`haproxy.pid` 和 `haproxy.sock`。复制该目录到
其他机器时，不需要复制这些运行时文件。

## 环境要求

运行环境需要 Bash 和 HAProxy。当前启动脚本不依赖 `redis-cli` 或 `redis-tools`。

Debian/Ubuntu 可以执行：

```bash
sudo apt update
sudo apt install haproxy
```

RHEL 及其兼容发行版（如 Rocky Linux、AlmaLinux 和 CentOS Stream）可以执行：

```bash
sudo dnf install haproxy
```

## 配置

部署时只需要检查和修改 `conf.d/00-redis-master.cfg` 中的三处内容。启动脚本会依次加载
`haproxy.cfg` 和 `conf.d` 目录中的所有 `.cfg` 文件。

### 1. HAProxy 监听地址

```haproxy
bind [::]:6379
```

该地址是客户端连接 HAProxy 的 Redis 入口。默认的 `[::]` 会监听所有 IPv6 网络接口；
是否同时接受 IPv4 连接取决于操作系统的 IPv6 Socket 设置。应配置防火墙规则，仅允许
可信客户端访问；如只允许本机客户端连接，可改为 `127.0.0.1`。

### 2. Redis 认证（可选）

Redis 启用密码认证时，在该目录执行：

```bash
./generate-auth-check.sh
```

输入 Redis 密码后，脚本会输出十六进制内容。按照脚本提示，只替换 AUTH 对应的
`tcp-check send-binary` 后面的内容：

```haproxy
tcp-check send-binary <生成的十六进制内容>
tcp-check expect string +OK
```

Redis 未启用密码认证时，删除上面两行 AUTH 检查配置。十六进制编码不具备保密能力，
应限制 `conf.d/00-redis-master.cfg` 的文件访问权限。

### 3. Redis 节点地址

```haproxy
server redis-0 127.0.0.1:6380
server redis-1 127.0.0.1:6381
```

将地址和端口改成实际 Redis 节点。HAProxy 必须能够访问所有节点，并且所有节点应使用相同
的认证配置。可以继续添加更多 `server` 配置行。

## 启动与停止

在该目录执行：

```bash
./start.sh
```

启动脚本会先组合检查 `haproxy.cfg` 和 `conf.d` 目录中配置文件的语法，然后在后台启动
HAProxy。`conf.d` 中的非隐藏 `.cfg` 文件按文件名字典序加载。脚本不会等待或检查 Redis
Master 是否可用；后端状态由 HAProxy 自身的 TCP 健康检查持续维护。

停止服务：

```bash
./stop.sh
```

修改配置后需要重启 HAProxy：

```bash
./stop.sh && ./start.sh
```

查看运行状态：

```bash
./status.sh
```

状态脚本检查 HAProxy 进程、`conf.d/00-redis-master.cfg` 中配置的监听端口，并通过 HAProxy Runtime API
显示各 backend 的 `UP/DOWN` 状态。脚本不会使用 `redis-cli` 或直接向 Redis 发送检查命令；
查询 Runtime API 需要安装 `nc` 和 `timeout`。HAProxy 正常且只有一个 Master backend 为
`UP` 时退出码为 `0`，异常时为 `1`，缺少检查命令时为 `2`。查询超时可通过
`STATUS_COMMAND_TIMEOUT` 设置，默认值为 `2` 秒。

如已安装 `redis-cli`，可以手动验证代理入口：

```bash
REDISCLI_AUTH='Redis 密码' redis-cli -h 127.0.0.1 -p 6379 role
```

返回的第一项应为 `master`。

## 健康检查规则

- HAProxy 使用 TCP 模式，最大连接数为 4096。
- 每秒检查一次 Redis 节点。
- 健康检查通过 `INFO replication` 判断节点是否包含 `role:master`。
- 连续两次检查失败后将节点标记为不可用，一次成功即可恢复。
- Master 下线时，HAProxy 会关闭与该节点的已有会话。
- 客户端和服务端的空闲超时均为 1 小时。

该配置未启用 TLS，适合本机或受信任的内网环境。用于生产环境时，还应配置服务管理、
日志轮转、凭据保护、网络访问控制和传输加密。

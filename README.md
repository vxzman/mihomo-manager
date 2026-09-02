# mihomo-manager

面向 **Linux 服务器裸跑 mihomo 内核**的 Web 面板：**单一 Go 二进制**（守护进程 + CLI），Vue 3 前端内嵌。通过面板一键切换 tun / socks / tproxy / redir-tproxy / server 五种透明代理模式，nft/ip 规则由守护进程编排并与 `mihomo@` 实例同生共死。

[![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)](go.mod)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> A single-binary mode manager for [mihomo](https://github.com/MetaCubeX/mihomo): manages tun / tproxy / redir-tproxy / socks / server modes, orchestrates nftables & policy-routing rules that live and die with each `mihomo@` instance, with an embedded Vue 3 web panel.

## 适用场景

- 服务器上已装 mihomo 内核（`/usr/local/bin/mihomo`），不想逐个手写 systemd 单元与 nftables/策略路由规则
- 需要在 TUN 虚拟网卡 / TPROXY / REDIR-TPROXY / SOCKS / 独立入站之间频繁切换
- 想要一个轻量 Web 面板 + CLI 管理，而不引入整套代理客户端

## 特性

- **5 种模式**：tun / socks / tproxy / redir-tproxy / server（独立入站，默认 mixed 20261）；socks 入站由端口驱动（默认 mixed 20260，面板可改）
- **规则生命周期**：启动 `mihomo@` 实例 → 延迟套用 nft/ip 规则 → 实例停止即清理（同生共死）；守护重启自动 reconcile 兜底；tun0 消失自动清理残留
- **回环避免双方式**：`meta skgid`（GID，优先）或 `meta mark`（路由 mark），二选一可配置
- **统一配置**：`/opt/mihomo-manager/manager.yaml` 是规则数字/env/预定义入站的唯一事实源
- **实时状态**：dbus 订阅 + SSE 推送，面板状态秒级刷新
- **配置同步**：`config_general.yaml` + 各模式预定义入站（socks 由 manager.yaml 的 `env.socks_port` 生成）→ `mihomo -t` 校验后生成各模式配置
- **面板体验**：切换按真实结果反馈（已启动/已停止/失败）；守护进程不可达时明确提示并一键重试；配置编辑器未保存修改有二次确认保护

## 目录结构

```
├── main.go              # 入口：go:embed 前端产物 + CLI 子命令分发
├── internal/
│   ├── api/             # REST API + SSE 推送
│   ├── cli/             # CLI 子命令（模式启停/status/config sync）
│   ├── config/          # manager.yaml 读写与同步
│   ├── intercept/       # tun/tproxy/redir-tproxy 规则编排（exec ip/nft）
│   ├── lifecycle/       # 模式生命周期（同生共死监控、reconcile）
│   ├── netlink/         # 只读状态检测 + tun0 link 事件
│   ├── server/          # 守护进程（systemd 常驻）
│   └── systemd/         # dbus 启停/状态订阅
├── web/                 # Vue 3 + Vite 前端（构建产物内嵌进二进制）
├── deploy/              # systemd 单元 + 安装模板配置 + deploy.sh
├── dev/                 # 本地开发 fixture（示例配置，无真实节点）
└── bash/                # 旧版 bash 脚本归档（移植参考，新版不再使用）
```

## 从源码编译

环境要求：Go 1.22+、Node.js 18+（Vite 5 前端构建）。

```bash
git clone git@github.com:vxzman/mihomo-manager.git
cd mihomo-manager

# 1. 构建前端（产物 web/dist/ 内嵌进二进制；跳过此步 go build 也能通过，但面板为占位页）
cd web && npm install && npm run build
cd ..

# 2. 构建后端（-ldflags 注入版本/编译信息，部署后可用 mihomo-manager info 核对是否最新）
go build -ldflags "\
  -X main.version=$(git describe --tags --always --dirty 2>/dev/null || echo dev) \
  -X main.commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown) \
  -X main.buildTime=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  -o mihomo-manager .

# 3. 验证产物
./mihomo-manager info
```

不注入 ldflags 也能构建，`mihomo-manager info` 会显示 `dev/unknown` 默认值（仅建议本地调试使用）。

编译产物的部署方法见下一节（无需在服务器上编译）。

## 部署到服务器（免编译，上传哪些文件）

前置：目标机已安装 mihomo 内核 `sudo cp mihomo /usr/local/bin/mihomo`。

**首次部署上传 4 个文件**：

| 文件 | 目标位置 |
|---|---|
| `mihomo-manager`（已编译二进制，前端已内嵌） | `/usr/local/bin/mihomo-manager` |
| `deploy/mihomo@.service` | `/etc/systemd/system/` |
| `deploy/mihomo-manager.service` | `/etc/systemd/system/` |
| `deploy/etc-mihomo/config_general.yaml`（模板配置） | `/etc/mihomo/` |

```bash
# 本机打包
tar czf /tmp/mm-dist.tar.gz mihomo-manager deploy/

# 上传并安装
scp /tmp/mm-dist.tar.gz 服务器:/tmp/
ssh 服务器
cd /tmp && tar xzf mm-dist.tar.gz         # 解出 /tmp/mihomo-manager + /tmp/deploy/
sudo /tmp/deploy/deploy.sh copy           # 装二进制+单元+建用户+启动守护
# 老 mihomo-web-panel 机器改用: sudo /tmp/deploy/deploy.sh upgrade（自动迁移 .conf）
```

手动安装等效命令：

```bash
sudo install -m 0755 /tmp/mihomo-manager /usr/local/bin/mihomo-manager
sudo cp /tmp/deploy/mihomo@.service /tmp/deploy/mihomo-manager.service /etc/systemd/system/
sudo mkdir -p /etc/mihomo && sudo cp /tmp/deploy/etc-mihomo/config_general.yaml /etc/mihomo/
sudo useradd --system --shell /usr/sbin/nologin --home-dir /var/lib/mihomo --no-create-home mihomo
sudo mkdir -p /var/lib/mihomo /var/log/mihomo && sudo chown mihomo:mihomo /var/lib/mihomo /var/log/mihomo
sudo systemctl daemon-reload && sudo systemctl enable --now mihomo-manager
```

**日常更新只传 1 个文件**：

```bash
scp mihomo-manager 服务器:/tmp/
ssh 服务器 'sudo install -m 0755 /tmp/mihomo-manager /usr/local/bin/mihomo-manager && sudo systemctl restart mihomo-manager'
```

## 常用命令

```bash
sudo mihomo-manager tun start              # 启动模式（tun|socks|tproxy|redir-tproxy|server）
sudo mihomo-manager tproxy stop            # 停止（规则自动清理）
sudo mihomo-manager status                 # 各模式/单元/规则状态
sudo mihomo-manager config sync            # 重新生成各模式配置（mihomo -t 校验）
mihomo-manager info                        # 版本/编译时间/目标平台（无需 root）
```

安装后检查：`/opt/mihomo-manager/manager.yaml` 里 tproxy/redir-tproxy 的 `exclude_gid` 与 `id -g mihomo` 一致（不一致会环路），可在面板「系统设置」修改。tun 模式的 `device: tun0` 按实际机器调整。socks 入站端口（默认 20260）在「系统设置 · SOCKS / SERVER」修改，保存后自动重新生成 `config_socks.yaml`；老版本 manager.yaml 里的 socks preset 会在守护进程启动时自动迁移为 `env.socks_port`。

## 监听地址与 IPv6（安全说明）

面板无鉴权，**默认仅监听 IPv4**（`0.0.0.0:8081`，不暴露 IPv6）。在 manager.yaml 中调整：

- 仅本机访问：`web_addr: "127.0.0.1:8081"`
- 显式启用 IPv6：`web_addr: "[::]:8081"`（仅 IPv6）或 `":8081"`（双栈，含 IPv4）

修改后 `sudo systemctl restart mihomo-manager` 生效（也可在面板「系统设置」修改）。

## nginx 反向代理配置示例

面板（`http://<host>:8081`）无内置鉴权，公网暴露建议经 nginx 反代并加 Basic Auth：

```nginx
server {
    listen 80;
    server_name mihomo.example.com;

    # 可选：面板无鉴权，建议开启 Basic Auth（先 htpasswd -c /etc/nginx/.htpasswd 用户名）
    # auth_basic "Mihomo Manager";
    # auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SSE 实时状态推送必须：关闭缓冲、放宽读超时
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
        proxy_set_header Connection '';
    }
}
```

HTTPS 用 certbot 免费证书：

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d mihomo.example.com
```

## 本地开发

```bash
./dev/run.sh                # 守护进程（dev fixture，不碰系统路径），面板 :8081
cd web && npm run dev       # 前端热更新（vite 代理到 :8081）
```

## 许可证

[MIT](LICENSE) © 2026 vxzman

# 遗留 bash 脚本归档

旧版 mihomoctl（bash 版）+ 透明代理规则脚本的遗留归档，**新版项目已不再使用**，仅供移植参考与旧布局部署。
新版等价实现为 Go 代码（`internal/intercept`、`internal/systemd`、`internal/lifecycle`）。

## 布局（以本目录为根，镜像服务器文件系统）

```
bash/
├── deploy.sh                       # 本布局的打包/安装/卸载脚本（pack/install/remove）
├── etc/
│   ├── mihomo/
│   │   ├── mihomo_tproxy.conf          # tproxy.sh 的 env 配置（gid 放行）
│   │   └── mihomo_redir-tproxy.conf    # redir-tproxy.sh 的 env 配置（mark 放行）
│   └── systemd/system/
│       ├── mihomo@.service             # ExecStart: /usr/local/bin/mihomo -f /etc/mihomo/config_%i.yaml
│       ├── tproxy@.service             # ExecStart: /usr/local/libexec/tproxy.sh start
│       └── redir-tproxy@.service       # ExecStart: /usr/local/libexec/redir-tproxy.sh start
└── usr/local/
    ├── bin/
    │   ├── mihomo                       # 假内核（配置测试直接通过），供本机无内核时联调
    │   └── mihomoctl                    # bash 版模式管理器（<mode> start|stop|status|log，--json）
    └── libexec/
        ├── tproxy.sh                    # TPROXY 规则脚本，internal/intercept 的移植母本
        └── redir-tproxy.sh              # REDIR-TPROXY 规则脚本
```

## 用法（需 root + 已安装 unit）

```bash
mihomoctl tun|tproxy|redir-tproxy|socks start|stop|restart|status|log
mihomoctl --json
./deploy.sh pack mihomoctl-bundle.tar.gz     # 打包本布局
./deploy.sh install mihomoctl-bundle.tar.gz # 服务器安装（安装后系统级可用）
./deploy.sh remove                           # 服务器移除（含规则清理）
```

## 本机非 root 可用性验证（2026-08-25）

| 检查 | 结果 |
|---|---|
| `bash -n` 全部 5 个脚本 | ✅ 语法通过 |
| unit ExecStart 与布局路径一致 | ✅ `/usr/local/bin/mihomo`、`/usr/local/libexec/{tproxy,redir-tproxy}.sh` |
| .conf 可 source，必需变量齐全 | ✅ TPROXY_PORT/FWMARK/TABLE_ID/NFTABLES_TABLE/ROUTING_MARK |
| `mihomoctl --json` 执行 | ✅ root 门禁正确触发（非 root 退出 1） |
| `tproxy.sh` 参数校验与 conf 读取链 | ✅ 报错路径符合预期（PROXYCORE 缺失 / conf 缺失） |
| 布局内 PATH 解析 `mihomo` | ✅ 命中 `usr/local/bin/mihomo` |

root 环境下完整验证：`sudo ./usr/local/bin/mihomoctl --json`（或 `sudo ./usr/local/bin/mihomoctl tun status`，均为只读）。
start/stop 需先经 `deploy.sh install` 安装 unit 与 conf 到系统路径。

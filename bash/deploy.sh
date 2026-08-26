#!/usr/bin/env bash
# Mihomo 部署脚本
#   用法:
#     deploy.sh pack [输出tar.gz]     在本机打包项目目录
#     deploy.sh install <包.tar.gz>   在服务器安装（需 root）
#     deploy.sh remove                在服务器移除全部相关文件（需 root）
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------- 公共 ----------------

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "FATAL: 需要 root 权限" >&2
        exit 1
    fi
}

# 清理 mihomo 各模式可能残留的策略路由与 nftables 规则
cleanup_firewall() {
    local pref
    local table

    for pref in 8999 9000 9001 9002 9010; do
        while ip rule del pref "$pref" 2>/dev/null; do
            :
        done
    done

    for table in "inet mihomo" "ip mihomo_tproxy4" "ip mihomo_redir_tproxy4"; do
        # shellcheck disable=SC2086
        nft delete table $table 2>/dev/null || true
    done

    for table in 100 2022; do
        ip route flush table "$table" 2>/dev/null || true
    done
}

# ---------------- pack ----------------

do_pack() {
    local out="${1:-$SELF_DIR/../mihomo-deploy-$(date +%Y%m%d-%H%M%S).tar.gz}"
    local items=()
    local item

    for item in bin etc usr var deploy.sh; do
        [ -e "$SELF_DIR/$item" ] && items+=("$item")
    done

    [ "${#items[@]}" -gt 0 ] || {
        echo "FATAL: 项目目录为空，无法打包" >&2
        exit 1
    }

    tar czf "$out" -C "$SELF_DIR" "${items[@]}"
    echo "[OK] 打包完成: $out"
    echo "    部署: scp '$out' server:/tmp/ && ssh server \"cd /tmp && tar xzf '$(basename "$out")' && ./deploy.sh install '$(basename "$out")'\""
}

# ---------------- install ----------------

do_install() {
    local tarball="${1:-}"
    local tmp
    local mihomo_gid

    [ -n "$tarball" ] || {
        echo "FATAL: 用法: $0 install <包.tar.gz>" >&2
        exit 1
    }
    require_root
    [ -f "$tarball" ] || {
        echo "FATAL: 包文件不存在: $tarball" >&2
        exit 1
    }

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    tar xzf "$tarball" -C "$tmp"

    for d in bin etc usr var; do
        [ -d "$tmp/$d" ] || {
            echo "FATAL: 包内缺少 $d/，不是有效的 mihomo 部署包" >&2
            exit 1
        }
    done

    # 1. 创建 mihomo 用户
    if ! id mihomo >/dev/null 2>&1; then
        useradd --system --shell /usr/sbin/nologin --home-dir /var/lib/mihomo --no-create-home mihomo
        echo "[OK] 已创建系统用户 mihomo (gid=$(id -g mihomo))"
    else
        echo "[SKIP] mihomo 用户已存在 (gid=$(id -g mihomo))"
    fi
    mihomo_gid="$(id -g mihomo)"

    # 2. 二进制
    install -m 0755 -o root -g root "$tmp/bin/mihomo" /usr/local/bin/mihomo
    echo "[OK] 已安装 /usr/local/bin/mihomo"

    # 3. 配置（YAML + env conf）
    install -d -m 0755 /etc/mihomo
    install -m 0644 -o root -g root "$tmp"/etc/mihomo/* /etc/mihomo/
    # tproxy 配置的 EXCLUDE_GID 与 mihomo 用户实际 gid 对齐（防止自身流量被拦截导致回环）
    if [ -f /etc/mihomo/mihomo_tproxy.conf ]; then
        sed -i -E "s/^EXCLUDE_GID=[0-9]+/EXCLUDE_GID=$mihomo_gid/" /etc/mihomo/mihomo_tproxy.conf
    fi
    echo "[OK] 已安装配置 -> /etc/mihomo/"

    # 4. systemd 单元
    install -m 0644 -o root -g root "$tmp"/etc/systemd/system/*.service /etc/systemd/system/
    echo "[OK] 已安装 systemd 单元"

    # 5. 控制脚本与规则脚本
    install -m 0755 -o root -g root "$tmp/usr/local/bin/mihomoctl" /usr/local/bin/mihomoctl
    install -d -m 0755 /usr/local/libexec
    install -m 0755 -o root -g root "$tmp"/usr/local/libexec/*.sh /usr/local/libexec/
    echo "[OK] 已安装 mihomoctl 与规则脚本"

    # 6. 数据与日志目录（mihomo 用户可写）
    install -d -m 0750 -o mihomo -g mihomo /var/lib/mihomo
    install -d -m 0750 -o mihomo -g mihomo /var/log/mihomo
    echo "[OK] 已创建 /var/lib/mihomo /var/log/mihomo"

    # 7. 面板提示（二进制不在包内）
    if [ ! -x /opt/mihomo-panel/mihomo-web-panel ]; then
        echo "[WARN] mihomo-panel.service 依赖 /opt/mihomo-panel/mihomo-web-panel，该二进制不在包内，需另行部署"
    fi

    systemctl daemon-reload
    echo "[OK] 安装完成。可用: mihomoctl {tun|tproxy|redir-tproxy|socks} start"
}

# ---------------- remove ----------------

do_remove() {
    local unit

    require_root

    echo "[1/4] 停止并禁用服务..."
    for unit in \
        mihomo@tun mihomo@tproxy mihomo@redir-tproxy mihomo@socks \
        tproxy@mihomo redir-tproxy@mihomo \
        mihomo-panel; do
        systemctl disable --now "$unit" 2>/dev/null || true
    done

    echo "[2/4] 清理策略路由与 nftables 残留..."
    cleanup_firewall

    echo "[3/4] 删除文件..."
    rm -f /usr/local/bin/mihomo
    rm -f /usr/local/bin/mihomoctl
    rm -f /usr/local/libexec/tproxy.sh
    rm -f /usr/local/libexec/redir-tproxy.sh
    rmdir /usr/local/libexec 2>/dev/null || true
    rm -f /etc/systemd/system/mihomo@.service
    rm -f /etc/systemd/system/mihomo-panel.service
    rm -f /etc/systemd/system/tproxy@.service
    rm -f /etc/systemd/system/redir-tproxy@.service
    rm -rf /etc/mihomo
    rm -rf /var/lib/mihomo
    rm -rf /var/log/mihomo
    rm -rf /opt/mihomo-panel

    echo "[4/4] 删除 mihomo 用户..."
    userdel mihomo 2>/dev/null || true

    systemctl daemon-reload
    echo "[OK] 已移除全部 mihomo 相关文件与服务"
}

# ---------------- Main ----------------

ACTION="${1:-}"
shift || true

case "$ACTION" in
    pack)
        do_pack "${1:-}"
        ;;
    install)
        do_install "${1:-}"
        ;;
    remove)
        do_remove
        ;;
    *)
        echo "用法:"
        echo "  $0 pack [输出tar.gz]       在本机打包"
        echo "  $0 install <包.tar.gz>     在服务器安装（需 root）"
        echo "  $0 remove                  在服务器移除全部相关文件（需 root）"
        exit 1
        ;;
esac

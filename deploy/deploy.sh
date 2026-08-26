#!/usr/bin/env bash
# mihomo-manager 部署脚本
#   用法:
#     deploy.sh install   首次安装（构建、装二进制/单元、初始化配置）
#     deploy.sh upgrade   从旧 mihomo-web-panel + mihomoctl 布局升级（自动迁移 .conf）
#     deploy.sh remove    移除全部相关文件与服务（含规则清理）
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SELF_DIR/.." && pwd)"

MANAGER_BIN=/usr/local/bin/mihomo-manager
CONFIG_DIR=/opt/mihomo-manager
ETC_MIHOMO=/etc/mihomo
SYSTEMD_DIR=/etc/systemd/system
MANAGER_YAML="$CONFIG_DIR/manager.yaml"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "FATAL: 需要 root 权限" >&2
        exit 1
    fi
}

# ---------------- 构建 ----------------

# 有已编译二进制则跳过构建（老机器无 Go 也能升级）
ensure_binary() {
    if [ -x "$ROOT_DIR/mihomo-manager" ]; then
        echo "[1/5] 使用已编译二进制: $ROOT_DIR/mihomo-manager"
        return 0
    fi
    build
}

build() {
    echo "[1/5] 构建 mihomo-manager..."
    (cd "$ROOT_DIR" && go build -ldflags="-s -w" -o mihomo-manager .)
    dist_files="$(find "$ROOT_DIR/web/dist" -type f 2>/dev/null | wc -l)"
    if [ "$dist_files" -le 1 ]; then
        echo "      [WARN] 前端未构建（当前为占位页）。构建方式: cd web && npm install && npm run build"
    fi
    echo "      [OK] 二进制: $ROOT_DIR/mihomo-manager"
}

# ---------------- 安装公共部分 ----------------

install_common() {
    echo "[2/5] 安装二进制与 systemd 单元..."
    install -m 0755 -o root -g root "$ROOT_DIR/mihomo-manager" "$MANAGER_BIN"
    install -m 0644 -o root -g root "$SELF_DIR/mihomo@.service" "$SYSTEMD_DIR/mihomo@.service"
    install -m 0644 -o root -g root "$SELF_DIR/mihomo-manager.service" "$SYSTEMD_DIR/mihomo-manager.service"
    echo "      [OK] 已安装 $MANAGER_BIN 与 systemd 单元"

    # 模板通用配置（仅首次；守护启动后自动生成各模式配置）
    install -d -m 0755 "$ETC_MIHOMO"
    if [ ! -f "$ETC_MIHOMO/config_general.yaml" ]; then
        install -m 0644 -o root -g root "$SELF_DIR/etc-mihomo/config_general.yaml" "$ETC_MIHOMO/config_general.yaml"
        echo "      [OK] 已安装模板配置 config_general.yaml"
    fi

    # manager.yaml（不存在时守护首启也会自动生成/迁移）
    install -d -m 0755 "$CONFIG_DIR"
}

ensure_user() {
    if ! id mihomo >/dev/null 2>&1; then
        useradd --system --shell /usr/sbin/nologin --home-dir /var/lib/mihomo --no-create-home mihomo
        echo "[3/5] 已创建系统用户 mihomo (gid=$(id -g mihomo))"
    else
        echo "[3/5] mihomo 用户已存在"
    fi
    install -d -m 0750 -o mihomo -g mihomo /var/lib/mihomo
    install -d -m 0750 -o mihomo -g mihomo /var/log/mihomo
}

enable_and_start() {
    systemctl daemon-reload
    systemctl enable mihomo-manager >/dev/null 2>&1 || true
    systemctl restart mihomo-manager
    echo "[5/5] 已启动 mihomo-manager。面板: http://<host>:8081"
}

# ---------------- install ----------------

do_install() {
    require_root
    ensure_binary
    install_common
    ensure_user
    echo "[4/5] manager.yaml 由守护进程首次启动自动生成（或使用 MIHOMO_MANAGER_CONFIG 指定）"
    enable_and_start
}

# ---------------- copy（免编译安装） ----------------
# 二进制已在本机构建完成（前端已内嵌），目标机无需 Go 工具链。

do_copy() {
    require_root
    ensure_binary
    install_common
    ensure_user
    echo "[4/5] manager.yaml 由守护进程首次启动自动生成（或使用 MIHOMO_MANAGER_CONFIG 指定）"
    enable_and_start
}

# ---------------- upgrade（老布局迁移） ----------------

do_upgrade() {
    require_root
    ensure_binary

    echo "[1/6] 停止旧服务..."
    for unit in mihomo-panel tproxy@mihomo redir-tproxy@mihomo; do
        systemctl disable --now "$unit" 2>/dev/null || true
    done

    # 先装新组件并启动守护：manager.yaml 的 .conf 迁移发生在守护首启，
    # 因此此时不能删旧 .conf。
    install_common
    ensure_user
    systemctl daemon-reload
    systemctl restart mihomo-manager
    sleep 2

    echo "[5/6] 清理旧布局文件..."
    if [ -f "$MANAGER_YAML" ]; then
        echo "      [OK] manager.yaml 已生成（含 .conf 迁移）: $MANAGER_YAML"
    else
        echo "      [WARN] manager.yaml 未生成，请检查 journalctl -u mihomo-manager"
    fi
    rm -f "$SYSTEMD_DIR/mihomo-panel.service" \
          "$SYSTEMD_DIR/tproxy@.service" \
          "$SYSTEMD_DIR/redir-tproxy@.service"
    rm -f /usr/local/bin/mihomoctl
    rm -f /usr/local/libexec/tproxy.sh /usr/local/libexec/redir-tproxy.sh
    rmdir /usr/local/libexec 2>/dev/null || true
    rm -f "$ETC_MIHOMO/mihomo_tproxy.conf" "$ETC_MIHOMO/mihomo_redir-tproxy.conf" \
          "$ETC_MIHOMO/mihomo_tproxy" "$ETC_MIHOMO/mihomo_redir-tproxy" \
          "$ETC_MIHOMO/preset_"*.yaml "$ETC_MIHOMO/.active_config" \
          "$ETC_MIHOMO/config_saved_"* "$ETC_MIHOMO/.meta" 2>/dev/null || true
    rm -rf "$ETC_MIHOMO/old" "$ETC_MIHOMO/versions"
    rm -rf /opt/mihomo-panel

    systemctl daemon-reload
    echo "[6/6] 升级完成。可用: mihomo-manager status"
}

# ---------------- remove ----------------

cleanup_firewall() {
    # 清理各模式可能残留的策略路由与 nftables 规则
    local pref table
    for pref in 8999 9000 9001 9002 9010; do
        while ip rule del pref "$pref" 2>/dev/null; do :; done
    done
    for table in "inet mihomo" "ip mihomo_tproxy4" "ip mihomo_redir_tproxy4"; do
        # shellcheck disable=SC2086
        nft delete table $table 2>/dev/null || true
    done
    for table in 100 2022; do
        ip route flush table "$table" 2>/dev/null || true
    done
}

do_remove() {
    require_root

    echo "[1/4] 停止并禁用服务..."
    for unit in \
        mihomo-manager \
        mihomo@tun mihomo@tproxy mihomo@redir-tproxy mihomo@socks mihomo@server \
        tproxy@mihomo redir-tproxy@mihomo mihomo-panel; do
        systemctl disable --now "$unit" 2>/dev/null || true
    done

    echo "[2/4] 清理策略路由与 nftables 残留..."
    cleanup_firewall

    echo "[3/4] 删除文件..."
    rm -f "$MANAGER_BIN"
    rm -f "$SYSTEMD_DIR/mihomo@.service" \
          "$SYSTEMD_DIR/mihomo-manager.service" \
          "$SYSTEMD_DIR/tproxy@.service" \
          "$SYSTEMD_DIR/redir-tproxy@.service" \
          "$SYSTEMD_DIR/mihomo-panel.service"
    rm -rf "$ETC_MIHOMO" /var/lib/mihomo /var/log/mihomo "$CONFIG_DIR"
    rm -f /usr/local/bin/mihomoctl
    rm -f /usr/local/libexec/tproxy.sh /usr/local/libexec/redir-tproxy.sh
    rmdir /usr/local/libexec 2>/dev/null || true

    echo "[4/4] 删除 mihomo 用户..."
    userdel mihomo 2>/dev/null || true

    systemctl daemon-reload
    echo "[OK] 已移除全部 mihomo-manager 相关文件与服务（未删除 /usr/local/bin/mihomo 内核二进制）"
}

# ---------------- Main ----------------

ACTION="${1:-}"
case "$ACTION" in
    install)  do_install ;;
    copy)     do_copy ;;
    upgrade)  do_upgrade ;;
    remove)   do_remove ;;
    *)
        echo "用法:"
        echo "  $0 install   首次安装（目标机编译）"
        echo "  $0 copy      免编译安装（复制已构建二进制，目标机无需 Go）"
        echo "  $0 upgrade   从旧布局升级（自动迁移 .conf → manager.yaml）"
        echo "  $0 remove    移除全部相关文件与服务"
        exit 1
        ;;
esac

package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// socks 入站由 env.socks_port 驱动：验证老 preset 迁移、默认值与生成结果。

func TestSocksPortMigrationFromPreset(t *testing.T) {
	cfg := Default()
	socks := cfg.Modes["socks"]
	// 模拟老版本 manager.yaml：端口藏在 preset 里，env 为空
	socks.Env = nil
	socks.Preset = "  - name: mixed-in\n    type: mixed\n    port: 25000\n    listen: 0.0.0.0\n    udp: true\n"
	fillDefaults(cfg)
	if socks.Env == nil || socks.Env.SocksPort != 25000 {
		t.Fatalf("迁移未提取端口: %+v", socks.Env)
	}
	if socks.Preset != "" {
		t.Fatalf("迁移后 socks preset 应为空，实际: %q", socks.Preset)
	}
}

func TestSocksPortKeptWhenSet(t *testing.T) {
	cfg := Default()
	cfg.Modes["socks"].Env.SocksPort = 26000
	fillDefaults(cfg)
	if got := cfg.Modes["socks"].Env.SocksPort; got != 26000 {
		t.Fatalf("已有端口被覆盖: %d", got)
	}
}

func TestSyncSocksGeneratedFromPort(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("MIHOMO_MANAGER_CONFIG", filepath.Join(dir, "manager.yaml"))
	cfg := Default()
	cfg.Dirs.ConfigDir = filepath.Join(dir, "etc")
	cfg.Modes["socks"].Env.SocksPort = 26000
	if err := Save(cfg); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(cfg.ConfigDir(), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cfg.GeneralPath(), []byte("mode: rule\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := SyncAll(cfg, ""); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(cfg.ConfigDir(), "config_socks.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "port: 26000") {
		t.Fatalf("生成的 socks 配置未包含端口 26000:\n%s", data)
	}
}

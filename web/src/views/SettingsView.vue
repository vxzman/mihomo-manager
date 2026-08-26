<script setup lang="ts">
import { onMounted, ref } from 'vue'
import Icon from '../components/Icon.vue'
import { fetchSettings, saveSettings, type ManagerSettings } from '../api'

const settings = ref<ManagerSettings | null>(null)
const message = ref<{ ok: boolean; text: string } | null>(null)
const saving = ref(false)

// 回环避免方式：gid（meta skgid）优先 / mark（meta mark）备选
const bypassTproxy = ref<'gid' | 'mark'>('gid')
const bypassRedir = ref<'gid' | 'mark'>('gid')

onMounted(async () => {
  try {
    settings.value = await fetchSettings()
    if ((settings.value.modes.tproxy?.env?.exclude_gid ?? 0) <= 0) bypassTproxy.value = 'mark'
    if ((settings.value.modes['redir-tproxy']?.env?.exclude_gid ?? 0) <= 0) bypassRedir.value = 'mark'
  } catch (e) {
    message.value = { ok: false, text: (e as Error).message }
  }
})

async function save() {
  if (!settings.value) return
  saving.value = true
  message.value = null
  try {
    const s = settings.value
    const update: Record<string, unknown> = { daemon: s.daemon, modes: {} }
    const modes = update.modes as Record<string, unknown>

    modes.tun = {
      routing: s.modes.tun?.routing ?? { rule_index: 0, table_index: 0 },
      preset: s.modes.tun?.preset ?? '',
    }

    for (const [name, sel] of [
      ['tproxy', bypassTproxy],
      ['redir-tproxy', bypassRedir],
    ] as const) {
      const env = { ...(s.modes[name]?.env ?? {}) }
      // 二选一：未被选中的方式清零（守护侧校验至少其一）
      if (sel.value === 'gid') env.routing_mark = 0
      else env.exclude_gid = 0
      modes[name] = { env, preset: s.modes[name]?.preset ?? '' }
    }

    for (const name of ['socks', 'server']) {
      if (s.modes[name]) modes[name] = { preset: s.modes[name]!.preset ?? '' }
    }

    await saveSettings(update)
    message.value = { ok: true, text: '设置已保存' }
  } catch (e) {
    message.value = { ok: false, text: (e as Error).message }
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div v-if="settings">
    <div class="page-head-row">
      <div>
        <h1 class="page-title"><Icon name="sliders" :size="22" /> 系统设置</h1>
        <p class="sub">
          写入 /opt/mihomo-manager/manager.yaml——规则数字、环境变量与预定义入站的唯一事实源。
        </p>
      </div>
      <button class="btn primary" :disabled="saving" @click="save">
        <Icon name="save" :size="15" /> 保存设置
      </button>
    </div>

    <!-- ─── 守护进程 ─── -->
    <section class="list card">
      <div class="list-head">守护进程</div>
      <div class="list-row">
        <span class="row-label">Web 监听地址</span>
        <div class="control">
          <input v-model="settings.daemon.web_addr" class="input" />
          <small class="row-hint">无鉴权：默认仅监听 IPv4</small>
        </div>
      </div>
      <div class="list-row">
        <span class="row-label">套规则延迟（毫秒）</span>
        <input v-model.number="settings.daemon.apply_delay_ms" type="number" class="input input-num" />
      </div>
      <div class="list-row">
        <span class="row-label">对账间隔</span>
        <input v-model="settings.daemon.reconcile_interval" class="input" />
      </div>
    </section>

    <!-- ─── TUN ─── -->
    <section class="list card">
      <div class="list-head">TUN · 路由索引（tun0 消失后按此清理）</div>
      <div class="list-row">
        <span class="row-label">ip rule 起始索引</span>
        <input v-model.number="settings.modes.tun!.routing!.rule_index" type="number" class="input input-num" />
      </div>
      <div class="list-row">
        <span class="row-label">路由表索引</span>
        <input v-model.number="settings.modes.tun!.routing!.table_index" type="number" class="input input-num" />
      </div>
      <details class="list-details">
        <summary>
          <span>预定义入站（preset）</span>
          <Icon name="chevron-down" :size="15" class="chev" />
        </summary>
        <div class="details-body">
          <textarea v-model="settings.modes.tun!.preset" class="code" style="min-height: 200px"></textarea>
        </div>
      </details>
    </section>

    <!-- ─── TPROXY ─── -->
    <section class="list card">
      <div class="list-head">TPROXY · 网络参数</div>
      <div class="list-row">
        <span class="row-label">TPROXY 端口（UDP）</span>
        <input v-model.number="settings.modes.tproxy!.env!.tproxy_port" type="number" class="input input-num" />
      </div>
      <div class="list-row">
        <span class="row-label">fwmark</span>
        <input v-model.number="settings.modes.tproxy!.env!.fwmark" type="number" class="input input-num" />
      </div>
      <div class="list-row">
        <span class="row-label">路由表 ID</span>
        <input v-model.number="settings.modes.tproxy!.env!.table_id" type="number" class="input input-num" />
      </div>
      <div class="list-row">
        <span class="row-label">nftables 表名</span>
        <input v-model="settings.modes.tproxy!.env!.nftables_table" class="input" />
      </div>
      <div class="list-row">
        <span class="row-label">回环避免方式</span>
        <div class="seg-mini">
          <button :class="{ on: bypassTproxy === 'gid' }" @click="bypassTproxy = 'gid'">GID 放行</button>
          <button :class="{ on: bypassTproxy === 'mark' }" @click="bypassTproxy = 'mark'">Mark 放行</button>
        </div>
      </div>
      <div class="list-row">
        <span class="row-label">排除 GID（mihomo 用户组）</span>
        <div class="control">
          <input v-model.number="settings.modes.tproxy!.env!.exclude_gid" type="number" class="input input-num" />
          <small class="row-hint">meta skgid · 放行 mihomo 用户组流量</small>
        </div>
      </div>
      <div class="list-row">
        <span class="row-label">路由 mark</span>
        <div class="control">
          <input v-model.number="settings.modes.tproxy!.env!.routing_mark" type="number" class="input input-num" />
          <small class="row-hint">meta mark · 放行已打标流量</small>
        </div>
      </div>
    </section>

    <!-- ─── REDIR-TPROXY ─── -->
    <section class="list card">
      <div class="list-head">REDIR-TPROXY · 网络参数（TCP REDIRECT + UDP TPROXY）</div>
      <div class="list-row">
        <span class="row-label">REDIRECT 端口（TCP）</span>
        <input v-model.number="settings.modes['redir-tproxy']!.env!.redirect_port" type="number" class="input input-num" />
      </div>
      <div class="list-row">
        <span class="row-label">TPROXY 端口（UDP）</span>
        <input v-model.number="settings.modes['redir-tproxy']!.env!.tproxy_port" type="number" class="input input-num" />
      </div>
      <div class="list-row">
        <span class="row-label">fwmark</span>
        <input v-model.number="settings.modes['redir-tproxy']!.env!.fwmark" type="number" class="input input-num" />
      </div>
      <div class="list-row">
        <span class="row-label">路由表 ID</span>
        <input v-model.number="settings.modes['redir-tproxy']!.env!.table_id" type="number" class="input input-num" />
      </div>
      <div class="list-row">
        <span class="row-label">nftables 表名</span>
        <input v-model="settings.modes['redir-tproxy']!.env!.nftables_table" class="input" />
      </div>
      <div class="list-row">
        <span class="row-label">回环避免方式</span>
        <div class="seg-mini">
          <button :class="{ on: bypassRedir === 'gid' }" @click="bypassRedir = 'gid'">GID 放行</button>
          <button :class="{ on: bypassRedir === 'mark' }" @click="bypassRedir = 'mark'">Mark 放行</button>
        </div>
      </div>
      <div class="list-row">
        <span class="row-label">排除 GID（mihomo 用户组）</span>
        <div class="control">
          <input v-model.number="settings.modes['redir-tproxy']!.env!.exclude_gid" type="number" class="input input-num" />
          <small class="row-hint">meta skgid · 放行 mihomo 用户组流量</small>
        </div>
      </div>
      <div class="list-row">
        <span class="row-label">路由 mark</span>
        <div class="control">
          <input v-model.number="settings.modes['redir-tproxy']!.env!.routing_mark" type="number" class="input input-num" />
          <small class="row-hint">meta mark · 放行已打标流量</small>
        </div>
      </div>
    </section>

    <!-- ─── SERVER / SOCKS ─── -->
    <section class="list card">
      <div class="list-head">SERVER / SOCKS · 预定义入站</div>
      <details class="list-details">
        <summary>
          <span>SERVER 独立入站（默认 mixed 20261）</span>
          <Icon name="chevron-down" :size="15" class="chev" />
        </summary>
        <div class="details-body">
          <textarea v-model="settings.modes.server!.preset" class="code" style="min-height: 160px"></textarea>
        </div>
      </details>
      <details class="list-details">
        <summary>
          <span>SOCKS 入站（默认 mixed 20260）</span>
          <Icon name="chevron-down" :size="15" class="chev" />
        </summary>
        <div class="details-body">
          <textarea v-model="settings.modes.socks!.preset" class="code" style="min-height: 160px"></textarea>
        </div>
      </details>
    </section>

    <div v-if="message" class="alert" :class="message.ok ? 'ok' : 'err'">
      <Icon :name="message.ok ? 'check-circle' : 'alert-triangle'" :size="16" />
      <span>{{ message.text }}</span>
    </div>
  </div>
  <div v-else class="card" style="color: var(--text-2)">加载设置中…</div>
</template>

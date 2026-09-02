<script setup lang="ts">
import { computed } from 'vue'
import Icon from '../components/Icon.vue'
import type { Status, ModeStatus } from '../api'

const props = defineProps<{
  status: Status | null
  // null = 尚未确定，true = 可达，false = 不可达
  connected: boolean | null
  loading: boolean
}>()

defineEmits<{ (e: 'action', mode: string, action: 'start' | 'stop'): void; (e: 'refresh'): void }>()

const modeOrder = ['tun', 'tproxy', 'redir-tproxy', 'socks', 'server']

const modeIcons: Record<string, string> = {
  tun: 'activity',
  tproxy: 'shuffle',
  'redir-tproxy': 'git-merge',
  socks: 'zap',
  server: 'server',
}

const entries = computed(() => {
  if (!props.status) return []
  return modeOrder
    .filter((n) => props.status!.modes[n])
    .map((n, i) => ({ name: n, index: i, icon: modeIcons[n] ?? 'zap', ...props.status!.modes[n] }))
})

// hero 展示活跃模式；瓦片展示其余模式（无活跃模式时展示全部）
const active = computed(() => entries.value.find((m) => m.active) ?? null)
const tiles = computed(() => entries.value.filter((m) => m !== active.value))

const rulesText: Record<string, string> = {
  present: '规则就位',
  missing: '规则缺失',
  clean: '无残留',
  leftover: '有残留',
  na: '不适用',
}

function rulesClass(m: ModeStatus): string {
  if (m.rules === 'present' || m.rules === 'clean') return 'active'
  if (m.rules === 'missing' || m.rules === 'leftover') return 'partial'
  return ''
}

const unitText: Record<string, string> = {
  active: '运行中',
  activating: '启动中',
  deactivating: '停止中',
  inactive: '已停止',
  failed: '失败',
  unknown: '未知',
}

function unitClass(s: string): string {
  if (s === 'active' || s === 'activating' || s === 'deactivating') return 'active'
  if (s === 'failed') return 'failed'
  return ''
}
</script>

<template>
  <div>
    <div class="page-head">
      <h1><Icon name="activity" :size="22" /> 运行状态</h1>
    </div>

    <!-- ─── hero：不可达 ─── -->
    <section v-if="!status && connected === false" class="hero error">
      <div class="hero-icon"><Icon name="alert-triangle" :size="30" /></div>
      <div class="hero-info">
        <div class="hero-title"><b>守护进程不可达</b></div>
        <div class="hero-unit">无法连接后端服务，请检查 mihomo-manager 守护进程是否运行</div>
      </div>
      <div class="hero-actions">
        <button class="btn primary lg" @click="$emit('refresh')">
          <Icon name="refresh-cw" :size="14" /> 重试
        </button>
      </div>
    </section>

    <!-- ─── hero：连接中 ─── -->
    <section v-else-if="!status" class="hero idle">
      <div class="hero-icon"><Icon name="power" :size="30" /></div>
      <div class="hero-info"><div class="hero-title"><b>连接中…</b></div></div>
    </section>

    <!-- ─── hero：活跃模式 ─── -->
    <section
      v-else-if="active"
      class="hero"
      :class="`c-${active.name}`"
    >
      <div class="hero-icon"><Icon :name="active.icon" :size="30" /></div>
      <div class="hero-info">
        <div class="hero-title">
          <b>{{ active.label }}</b>
          <small>{{ active.name }}</small>
        </div>
        <div class="hero-unit">{{ active.unit }}</div>
        <div class="hero-badges">
          <span class="badge" :class="unitClass(active.unit_state)">
            <span class="dot" :class="{ on: active.active }"></span>
            {{ unitText[active.unit_state] ?? active.unit_state }}
          </span>
          <span class="badge" :class="rulesClass(active)">
            <Icon name="activity" :size="12" />
            {{ rulesText[active.rules] ?? active.rules }}
          </span>
        </div>
      </div>
      <div class="hero-actions">
        <button class="btn danger lg" :disabled="loading" @click="$emit('action', active.name, 'stop')">
          <Icon name="stop" :size="14" /> 停止
        </button>
      </div>
    </section>

    <section v-else class="hero idle">
      <div class="hero-icon"><Icon name="power" :size="30" /></div>
      <div class="hero-info">
        <div class="hero-title"><b>无活跃模式</b></div>
      </div>
    </section>

    <!-- ─── 模式瓦片 ─── -->
    <div class="tiles">
      <div
        v-for="m in tiles"
        :key="m.name"
        class="tile"
        :class="`c-${m.name}`"
        :style="{ animationDelay: `${m.index * 0.05}s` }"
      >
        <div class="tile-head">
          <div class="tile-icon"><Icon :name="m.icon" :size="19" /></div>
          <div class="tile-title">
            <b>{{ m.label }}</b>
            <small>{{ m.name }}</small>
          </div>
          <span class="tile-state" :class="{ on: m.active }" :title="unitText[m.unit_state] ?? m.unit_state"></span>
        </div>

        <div class="tile-meta">
          <span v-if="m.unit_state !== 'inactive'" class="badge" :class="unitClass(m.unit_state)">
            {{ unitText[m.unit_state] ?? m.unit_state }}
          </span>
          <span class="badge" :class="rulesClass(m)">
            {{ rulesText[m.rules] ?? m.rules }}
          </span>
        </div>

        <button class="btn primary tile-start" :disabled="loading" @click="$emit('action', m.name, 'start')">
          <Icon name="power" :size="14" /> 启动
        </button>
      </div>
    </div>
  </div>
</template>

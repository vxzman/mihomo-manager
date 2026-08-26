<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import StatusView from './views/StatusView.vue'
import ConfigView from './views/ConfigView.vue'
import SettingsView from './views/SettingsView.vue'
import Icon from './components/Icon.vue'
import { fetchStatus, modeAction, subscribeStatus, type Status } from './api'

type View = 'status' | 'config' | 'settings'
const view = ref<View>('status')
const status = ref<Status | null>(null)
const loading = ref(false)
const message = ref<{ ok: boolean; text: string } | null>(null)
let messageTimer: ReturnType<typeof setTimeout> | null = null

let unsubscribe: (() => void) | null = null

onMounted(() => {
  refresh()
  unsubscribe = subscribeStatus((s) => (status.value = s))
})

onUnmounted(() => {
  unsubscribe?.()
  if (messageTimer) clearTimeout(messageTimer)
})

async function refresh() {
  try {
    status.value = await fetchStatus()
  } catch {
    /* 守护进程暂不可达，SSE 重连后恢复 */
  }
}

async function onModeAction(mode: string, action: 'start' | 'stop') {
  loading.value = true
  try {
    await modeAction(mode, action)
    showMessage(true, `模式 ${mode} ${action === 'start' ? '启动' : '停止'}指令已执行`)
    await refresh()
  } catch (e) {
    showMessage(false, (e as Error).message)
  } finally {
    loading.value = false
  }
}

function showMessage(ok: boolean, text: string) {
  message.value = { ok, text }
  if (messageTimer) clearTimeout(messageTimer)
  messageTimer = setTimeout(() => (message.value = null), 5000)
}

const nav: { key: View; label: string; icon: string }[] = [
  { key: 'status', label: '状态', icon: 'activity' },
  { key: 'config', label: '配置', icon: 'file' },
  { key: 'settings', label: '设置', icon: 'sliders' },
]

const activeLabel = () => {
  const s = status.value
  if (!s || !s.active_mode) return '无活跃模式'
  return s.modes[s.active_mode]?.label ?? s.active_mode
}
</script>

<template>
  <div class="app">
    <header class="topnav">
      <div class="logo">
        <div class="logo-mark"><Icon name="cat" :size="20" /></div>
        <div class="logo-text">
          <b>Mihomo Manager</b>
        </div>
      </div>

      <nav class="seg">
        <button
          v-for="item in nav"
          :key="item.key"
          class="seg-item"
          :class="{ active: view === item.key }"
          @click="view = item.key"
        >
          <Icon :name="item.icon" :size="15" />
          {{ item.label }}
        </button>
      </nav>

      <div class="topnav-chip">
        <span class="dot" :class="{ on: !!status?.active_mode }"></span>
        <span>{{ activeLabel() }}</span>
      </div>
    </header>

    <main class="main">
      <StatusView v-if="view === 'status'" :status="status" :loading="loading" @action="onModeAction" />
      <ConfigView v-else-if="view === 'config'" />
      <SettingsView v-else />

      <transition name="fade">
        <div v-if="message" class="toast" :class="message.ok ? 'ok' : 'err'">
          <Icon :name="message.ok ? 'check-circle' : 'alert-triangle'" :size="16" />
          {{ message.text }}
        </div>
      </transition>
    </main>
  </div>
</template>

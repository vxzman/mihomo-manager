<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import Icon from '../components/Icon.vue'
import { configSync, fetchGeneral, fetchModeConfig, fetchSettings, saveGeneral } from '../api'

const target = ref('general')
const modes = ref<string[]>([])
const content = ref('')
const loading = ref(false)
const message = ref<{ ok: boolean; text: string } | null>(null)
const isGeneral = ref(true)

const fileName = ref('config_general.yaml')

onMounted(async () => {
  try {
    const settings = await fetchSettings()
    modes.value = Object.keys(settings.modes)
  } catch (e) {
    message.value = { ok: false, text: (e as Error).message }
  }
  await load()
})

watch(target, () => load())

async function load() {
  loading.value = true
  message.value = null
  try {
    isGeneral.value = target.value === 'general'
    fileName.value = isGeneral.value
      ? 'config_general.yaml'
      : `config_${target.value}.yaml（自动生成，只读）`
    content.value = isGeneral.value ? await fetchGeneral() : await fetchModeConfig(target.value)
  } catch (e) {
    message.value = { ok: false, text: (e as Error).message }
  } finally {
    loading.value = false
  }
}

async function save() {
  message.value = null
  try {
    await saveGeneral(content.value)
    message.value = { ok: true, text: '通用配置已保存，各模式配置已同步生成' }
  } catch (e) {
    message.value = { ok: false, text: (e as Error).message }
  }
}

async function sync() {
  message.value = null
  try {
    await configSync()
    message.value = { ok: true, text: '各模式配置已重新生成' }
    if (!isGeneral.value) await load()
  } catch (e) {
    message.value = { ok: false, text: (e as Error).message }
  }
}
</script>

<template>
  <div>
    <div class="page-head">
      <h1><Icon name="file" :size="22" /> 配置管理</h1>
      <p class="sub">
        通用配置是唯一编辑入口；各模式配置由「通用配置 + manager.yaml 预定义入站」合并生成（校验通过后原子写入）。
      </p>
    </div>

    <div class="config-panes">
      <!-- ─── 左：文件列表 ─── -->
      <aside class="file-pane">
        <div class="pane-title">配置文件</div>
        <button
          class="file-row"
          :class="{ active: target === 'general' }"
          @click="target = 'general'"
        >
          <Icon name="file" :size="14" />
          <span>config_general.yaml</span>
        </button>
        <button
          v-for="m in modes"
          :key="m"
          class="file-row"
          :class="{ active: target === m }"
          @click="target = m"
        >
          <Icon name="file" :size="14" />
          <span>config_{{ m }}.yaml</span>
          <span class="ftag">自动生成</span>
        </button>
      </aside>

      <!-- ─── 右：编辑器 ─── -->
      <section class="editor-pane">
        <div class="editor-toolbar">
          <span class="file-badge"><Icon name="file" :size="13" /> {{ fileName }}</span>
          <span class="spacer"></span>
          <button v-if="isGeneral" class="btn primary" :disabled="loading" @click="save">
            <Icon name="save" :size="15" /> 保存并同步
          </button>
          <button v-else class="btn" :disabled="loading" @click="sync">
            <Icon name="refresh-cw" :size="15" /> 重新生成
          </button>
          <button class="btn ghost" :disabled="loading" @click="load">
            <Icon name="refresh-cw" :size="15" /> 刷新
          </button>
        </div>

        <textarea
          v-model="content"
          class="code"
          :readonly="!isGeneral"
          spellcheck="false"
          :style="{ opacity: isGeneral ? 1 : 0.8 }"
        ></textarea>

        <div v-if="message" class="alert" :class="message.ok ? 'ok' : 'err'">
          <Icon :name="message.ok ? 'check-circle' : 'alert-triangle'" :size="16" />
          <span>{{ message.text }}</span>
        </div>
      </section>
    </div>
  </div>
</template>

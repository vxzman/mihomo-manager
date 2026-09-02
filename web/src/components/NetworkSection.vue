<script setup lang="ts">
import type { EnvSettings } from '../api'

// TPROXY / REDIR-TPROXY 共用的网络参数表单。
// env 为响应式对象，表单直接就地编辑；bypass 二选一状态由父组件持有。
defineProps<{
  head: string
  env: EnvSettings
  bypass: 'gid' | 'mark'
  showRedirect?: boolean
}>()

defineEmits<{ (e: 'update:bypass', v: 'gid' | 'mark'): void }>()
</script>

<template>
  <section class="list card">
    <div class="list-head">{{ head }}</div>
    <div v-if="showRedirect" class="list-row">
      <span class="row-label">REDIRECT 端口（TCP）</span>
      <input v-model.number="env.redirect_port" type="number" class="input input-num" />
    </div>
    <div class="list-row">
      <span class="row-label">TPROXY 端口（UDP）</span>
      <input v-model.number="env.tproxy_port" type="number" class="input input-num" />
    </div>
    <div class="list-row">
      <span class="row-label">fwmark</span>
      <input v-model.number="env.fwmark" type="number" class="input input-num" />
    </div>
    <div class="list-row">
      <span class="row-label">路由表 ID</span>
      <input v-model.number="env.table_id" type="number" class="input input-num" />
    </div>
    <div class="list-row">
      <span class="row-label">nftables 表名</span>
      <input v-model="env.nftables_table" class="input" />
    </div>
    <div class="list-row">
      <span class="row-label">回环避免方式</span>
      <div class="seg-mini">
        <button :class="{ on: bypass === 'gid' }" @click="$emit('update:bypass', 'gid')">GID 放行</button>
        <button :class="{ on: bypass === 'mark' }" @click="$emit('update:bypass', 'mark')">Mark 放行</button>
      </div>
    </div>
    <div class="list-row">
      <span class="row-label">排除 GID（mihomo 用户组）</span>
      <div class="control">
        <input v-model.number="env.exclude_gid" type="number" class="input input-num" :disabled="bypass !== 'gid'" />
        <small class="row-hint">
          {{ bypass === 'gid' ? 'meta skgid · 放行 mihomo 用户组流量' : '当前方式未启用，保存时将清零' }}
        </small>
      </div>
    </div>
    <div class="list-row">
      <span class="row-label">路由 mark</span>
      <div class="control">
        <input v-model.number="env.routing_mark" type="number" class="input input-num" :disabled="bypass !== 'mark'" />
        <small class="row-hint">
          {{ bypass === 'mark' ? 'meta mark · 放行已打标流量' : '当前方式未启用，保存时将清零' }}
        </small>
      </div>
    </div>
  </section>
</template>

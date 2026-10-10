<script setup lang="ts">
import { CircleAlert, Inbox } from '@lucide/vue'
import { NButton, NSpin } from 'naive-ui'

defineProps<{ loading?: boolean; error?: string; title?: string; description?: string }>()
defineEmits<{ retry: [] }>()
</script>

<template>
  <div
    class="state-panel"
    role="status"
    aria-live="polite"
  >
    <NSpin
      v-if="loading"
      size="medium"
    />
    <CircleAlert
      v-else-if="error"
      :size="34"
      class="accent"
    />
    <Inbox
      v-else
      :size="38"
      :stroke-width="1.3"
    />
    <h3 class="state-title">
      {{ loading ? '正在加载…' : error ? title || '加载失败' : title || '暂无内容' }}
    </h3>
    <p
      v-if="error || description"
      class="state-description"
    >
      {{ error || description }}
    </p>
    <NButton
      v-if="error"
      secondary
      @click="$emit('retry')"
    >
      重新加载
    </NButton>
    <slot />
  </div>
</template>

<style scoped>
.state-panel {
  display: flex;
  min-height: 285px;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 15px;
  padding: 40px 20px;
  text-align: center;
  color: var(--muted);
  animation: content-reveal var(--motion-normal) var(--motion-ease);
}
.accent {
  color: var(--accent);
}
.state-title {
  font-size: 16px;
  font-weight: 500;
  color: var(--text);
}
.state-description {
  max-width: 470px;
  font-size: 14px;
  line-height: 1.8;
}
</style>

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
    <h3>
      {{ loading ? '正在加载…' : error ? '无法连接节目服务' : title || '暂无内容' }}
    </h3>
    <p v-if="error || description">{{ error || description }}</p>
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
  min-height: 285px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 15px;
  text-align: center;
  padding: 40px 20px;
  color: var(--muted);
}

.state-panel h3 {
  color: var(--text);
  font-size: 16px;
  font-weight: 500;
}

.state-panel p {
  font-size: var(--font-size-meta);
  line-height: 1.8;
  max-width: 470px;
}
</style>

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
      class="accent text-accent"
    />
    <Inbox
      v-else
      :size="38"
      :stroke-width="1.3"
    />
    <h3 class="text-body font-medium text-main">
      {{ loading ? '正在加载…' : error ? title || '加载失败' : title || '暂无内容' }}
    </h3>
    <p
      v-if="error || description"
      class="max-w-117.5 text-meta leading-[1.8]"
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
@reference '../styles/global.css';

@layer components {
  .state-panel {
    @apply flex min-h-71.25 animate-content-reveal flex-col items-center justify-center gap-3.75;
    @apply px-5 py-10 text-center text-muted;
  }
}
</style>

<script setup lang="ts">
import { computed } from 'vue'
import { NButton } from 'naive-ui'

const props = withDefaults(
  defineProps<{
    pending?: boolean
    held?: boolean
    cached?: boolean
    fetchedAt?: string | null
    refreshError?: string
    cacheWarning?: string
  }>(),
  {
    pending: false,
    held: false,
    cached: false,
    fetchedAt: null,
    refreshError: '',
    cacheWarning: '',
  },
)
const emit = defineEmits<{ accept: []; retry: [] }>()
const fetchedLabel = computed(() =>
  props.fetchedAt ? new Date(props.fetchedAt).toLocaleString('zh-CN') : '',
)
</script>

<template>
  <section
    v-if="pending || refreshError || cacheWarning"
    class="programme-update"
    aria-label="节目数据状态"
  >
    <div
      class="programme-update-copy"
      role="status"
    >
      <p v-if="cached">
        正在显示缓存内容
        <span v-if="fetchedLabel">· 更新于 {{ fetchedLabel }}</span>
      </p>
      <p v-if="refreshError">刷新失败，已保留当前内容：{{ refreshError }}</p>
      <p v-if="cacheWarning">{{ cacheWarning }}</p>
      <p v-if="pending && held">预览或批量选择结束后可应用新内容。</p>
    </div>
    <NButton
      v-if="pending"
      class="programme-update-apply"
      secondary
      :disabled="held"
      @click="emit('accept')"
    >
      发现新内容
    </NButton>
    <NButton
      v-if="refreshError"
      secondary
      @click="emit('retry')"
    >
      重试刷新
    </NButton>
  </section>
</template>

<style scoped>
.programme-update {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 12px;
  padding: 11px 14px;
  margin-bottom: 16px;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--panel);
}
.programme-update-copy {
  flex: 1 1 240px;
  color: var(--muted);
  font-size: 12px;
  line-height: 1.7;
}
@media (width < 760px) {
  .programme-update {
    padding: 12px;
  }
}
</style>

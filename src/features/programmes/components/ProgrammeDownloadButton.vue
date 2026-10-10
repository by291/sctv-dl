<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { NButton, NDropdown } from 'naive-ui'
import { ChevronDown, Download } from '@lucide/vue'

import { resolveVideo } from '@/features/programmes/model/video-variants'

import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'

const props = defineProps<{
  contents: ProgrammeContent[]
  label: string
  ariaLabel?: string
  primary?: boolean
  compact?: boolean
  disabled?: boolean
  loading?: boolean
}>()
const emit = defineEmits<{ download: [quality: Quality] }>()
const show = ref(false)
const enabled = computed(
  () =>
    !props.disabled &&
    !props.loading &&
    props.contents.length > 0 &&
    props.contents.every((content) => !!resolveVideo(content, 'standard')),
)
const options = computed(() =>
  [
    {
      label: '标准',
      key: 'standard',
      disabled: !props.contents.some((content) => !!content.video),
    },
    {
      label: '流畅',
      key: 'smooth',
      disabled: !props.contents.some((content) => !!content.smoothVideo),
    },
  ].map((option) => ({
    ...option,
    props: { role: 'menuitem', 'aria-disabled': option.disabled },
  })),
)

function selectQuality(key: string | number) {
  if (enabled.value && (key === 'standard' || key === 'smooth')) {
    emit('download', key)
  }
}

// A changed selection must not leave a menu open for the previous operation.
watch(
  () => props.contents,
  () => {
    show.value = false
  },
)
</script>

<template>
  <NDropdown
    v-model:show="show"
    trigger="click"
    :placement="compact ? 'bottom-start' : 'bottom-end'"
    :width="144"
    size="medium"
    :theme-overrides="{ fontSizeMedium: '14px', optionHeightMedium: '40px', padding: '4px 0' }"
    :options="options"
    :disabled="!enabled"
    :menu-props="
      () => ({
        role: 'menu',
        'aria-label': '下载画质',
      })
    "
    @select="selectQuality"
  >
    <NButton
      class="download-button"
      :class="{ 'compact-download': compact }"
      :theme-overrides="{
        heightMedium: compact ? '36px' : '40px',
        fontSizeMedium: '14px',
        fontWeight: compact ? '500' : '600',
        paddingMedium: compact ? '0 12px' : '0 16px',
        iconSizeMedium: '16px',
        border: '1px solid var(--line)',
      }"
      :type="primary ? 'primary' : 'default'"
      :disabled="!enabled"
      :loading="loading"
      :aria-label="ariaLabel || label"
      aria-haspopup="menu"
      :aria-expanded="show"
    >
      <template #icon><Download :size="16" /></template>
      {{ label }}
      <ChevronDown
        class="download-chevron"
        :size="14"
      />
    </NButton>
  </NDropdown>
</template>

<style scoped>
.download-chevron {
  margin-left: 6px;
}
@media (width < 760px) {
  .download-button {
    min-height: 44px;
  }
}
</style>

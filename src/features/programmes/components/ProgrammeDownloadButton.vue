<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { NButton, NDropdown } from 'naive-ui'
import { ChevronDown, Download } from '@lucide/vue'

import { resolveVideo } from '../video'

import type { ProgrammeContent, Quality } from '../types'

const props = defineProps<{
  contents: ProgrammeContent[]
  label: string
  ariaLabel?: string
  primary?: boolean
}>()
const emit = defineEmits<{ download: [quality: Quality] }>()
const show = ref(false)
const enabled = computed(
  () =>
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
    placement="bottom-end"
    :width="128"
    :options="options"
    :disabled="!enabled"
    :menu-props="() => ({ role: 'menu', 'aria-label': '下载画质' })"
    @select="selectQuality"
  >
    <NButton
      :type="primary ? 'primary' : 'default'"
      :secondary="!primary"
      :disabled="!enabled"
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

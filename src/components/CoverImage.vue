<script setup lang="ts">
import { ref, watch } from 'vue'
import { Tv } from '@lucide/vue'

const props = defineProps<{ src: string | null; alt: string }>()
const failed = ref(false)
watch(
  () => props.src,
  () => {
    failed.value = false
  },
)
</script>

<template>
  <div class="cover-image size-full overflow-hidden bg-subtle">
    <img
      v-if="src && !failed"
      :src="src"
      :alt="alt"
      class="block size-full object-cover"
      loading="lazy"
      referrerpolicy="no-referrer"
      @error="failed = true"
    />
    <div
      v-else
      class="cover-fallback"
    >
      <Tv
        :size="34"
        :stroke-width="1.4"
      />
      <span class="text-meta">{{ alt }}</span>
    </div>
  </div>
</template>

<style scoped>
@reference '../styles/global.css';

@layer components {
  .cover-fallback {
    @apply flex size-full min-h-[85px] flex-col items-center justify-center gap-2;
    @apply bg-[linear-gradient(125deg,var(--subtle),var(--accent-soft))] p-3 text-center text-muted;
  }
}
</style>

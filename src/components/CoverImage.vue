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
  <div class="cover-image">
    <img
      v-if="src && !failed"
      :src="src"
      :alt="alt"
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
      <span>{{ alt }}</span>
    </div>
  </div>
</template>

<style scoped>
.cover-image {
  width: 100%;
  height: 100%;
  overflow: hidden;
  background: var(--subtle);
}

.cover-image img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.cover-fallback {
  width: 100%;
  height: 100%;
  min-height: 85px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  background: linear-gradient(125deg, var(--subtle), var(--accent-soft));
  color: var(--muted);
  text-align: center;
  padding: 12px;
}

.cover-fallback span {
  font-size: 11px;
}
</style>

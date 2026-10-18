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
      class="cover-photo"
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
      <span
        class="cover-label"
        :title="alt"
      >
        {{ alt }}
      </span>
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
.cover-photo {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.cover-fallback {
  display: flex;
  width: 100%;
  height: 100%;
  min-height: 85px;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  background: linear-gradient(125deg, var(--subtle), var(--accent-soft));
  padding: 12px;
  text-align: center;
  color: var(--muted);
}
.cover-label {
  width: 100%;
  flex-shrink: 0;
  overflow: hidden;
  font-size: 14px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>

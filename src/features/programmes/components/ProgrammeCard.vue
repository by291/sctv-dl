<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { ArrowUpRight, Star } from '@lucide/vue'

import CoverImage from '../../../components/CoverImage.vue'

import type { Programme } from '../types'

defineProps<{ programme: Programme; favourite: boolean }>()
const emit = defineEmits<{ toggleFavourite: [id: string] }>()
</script>

<template>
  <article class="programme-card">
    <RouterLink
      :to="`/programmes/${programme.id}`"
      class="programme-cover group/cover relative block"
    >
      <CoverImage
        class="aspect-video"
        :src="programme.cover"
        :alt="programme.name"
      />
      <span class="cover-open">
        <ArrowUpRight :size="20" />
      </span>
    </RouterLink>

    <button
      class="favourite-button"
      :class="{ saved: favourite }"
      :aria-label="`${favourite ? '取消收藏' : '收藏'}${programme.name}`"
      :aria-pressed="favourite"
      @click="emit('toggleFavourite', programme.id)"
    >
      <Star
        :size="16"
        :fill="favourite ? 'currentColor' : 'none'"
      />
    </button>

    <RouterLink
      :to="`/programmes/${programme.id}`"
      class="programme-caption"
    >
      <div>
        <h3 class="text-body leading-[1.5] font-semibold">{{ programme.name }}</h3>
      </div>
      <ArrowUpRight
        class="text-[#b2b8c0] max-[440px]:hidden"
        :size="18"
      />
    </RouterLink>
  </article>
</template>

<style scoped>
@reference '../../../styles/global.css';

@layer components {
  .programme-card {
    @apply relative overflow-hidden rounded-[11px] border border-line bg-panel;
    @apply transition-[transform,box-shadow] duration-200 ease-[ease];
    @apply hover:shadow-[0_8px_24px_#20232a0d] hover:[transform:translateY(-3px)];
  }

  .cover-open {
    @apply absolute inset-0 grid place-items-center bg-[#13192633] text-white opacity-0;
    @apply transition-opacity duration-200 ease-[ease] group-hover/cover:opacity-100;
  }

  .favourite-button {
    @apply absolute top-[10px] right-[10px] grid size-9 place-items-center rounded-[7px] border;
    @apply border-[#ffffff50] backdrop-blur-[8px] transition-colors duration-[140ms] ease-[ease];
    @apply bg-[#17223145] text-white;
    @apply hover:bg-[#ffffffdf] hover:text-accent;
  }

  .favourite-button.saved {
    @apply bg-[#ffffffdf] text-accent;
  }

  .favourite-button.saved :deep(svg) {
    @apply animate-favourite-pop;
  }

  .programme-caption {
    @apply flex items-center justify-between gap-2 px-4 py-2.5;

    @variant max-[760px] {
      @apply px-3;
    }
  }
}
</style>

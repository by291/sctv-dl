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
      class="programme-cover"
    >
      <CoverImage
        class="programme-image"
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
        <h3 class="programme-name">{{ programme.name }}</h3>
      </div>
      <ArrowUpRight
        class="caption-arrow"
        :size="18"
      />
    </RouterLink>
  </article>
</template>

<style scoped>
.programme-card {
  position: relative;
  overflow: hidden;
  border-radius: 11px;
  border: 1px solid var(--line);
  background: var(--panel);
  transition:
    transform 200ms ease,
    box-shadow 200ms ease;
}
.programme-cover {
  position: relative;
  display: block;
}
.programme-image {
  aspect-ratio: 16 / 9;
}
.cover-open {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  background: #13192633;
  color: white;
  opacity: 0;
  transition: opacity 200ms ease;
}
.favourite-button {
  position: absolute;
  top: 10px;
  right: 10px;
  display: grid;
  width: 36px;
  height: 36px;
  place-items: center;
  border-radius: 7px;
  border: 1px solid #ffffff50;
  backdrop-filter: blur(8px);
  background: #17223145;
  color: white;
  transition:
    color 140ms ease,
    background-color 140ms ease,
    border-color 140ms ease;
}
.favourite-button.saved {
  background: #ffffffdf;
  color: var(--accent);
}
.favourite-button.saved :deep(svg) {
  animation: favourite-pop 220ms var(--motion-ease);
}
.programme-caption {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 10px 16px;
}
.programme-name {
  font-size: 16px;
  line-height: 1.5;
  font-weight: 600;
}
.caption-arrow {
  color: #b2b8c0;
}
@media (hover: hover) {
  .programme-card:hover {
    transform: translateY(-3px);
    box-shadow: 0 8px 24px #20232a0d;
  }
  .programme-cover:hover .cover-open {
    opacity: 1;
  }
  .favourite-button:hover {
    background: #ffffffdf;
    color: var(--accent);
  }
}
@media (width < 760px) {
  .favourite-button {
    top: 8px;
    right: 8px;
    width: 44px;
    height: 44px;
  }
  .programme-caption {
    padding-inline: 12px;
  }
}
@media (width < 440px) {
  .caption-arrow {
    display: none;
  }
}
</style>

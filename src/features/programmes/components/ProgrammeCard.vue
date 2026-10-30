<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { ArrowUpRight, Star } from '@lucide/vue'

import CoverImage from '@/shared/components/CoverImage.vue'
import { useProgrammeCoverNavigation } from '@/features/programmes/composables/useProgrammeCoverNavigation'

import type { Programme } from '@/features/programmes/model/programme'

const props = defineProps<{ programme: Programme; favourite: boolean }>()
const emit = defineEmits<{ toggleFavourite: [id: string] }>()

const { coverStyle, openProgramme } = useProgrammeCoverNavigation(() => props.programme.id)
</script>

<template>
  <article class="programme-card">
    <RouterLink
      :to="`/programmes/${programme.id}`"
      class="programme-cover"
      @click.capture="openProgramme"
    >
      <CoverImage
        class="programme-image"
        :style="coverStyle"
        :src="programme.cover"
        :alt="programme.name"
      />
      <span class="cover-open">
        <ArrowUpRight :size="19" />
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
      @click.capture="openProgramme"
    >
      <h3
        class="programme-name"
        :title="programme.name"
      >
        {{ programme.name }}
      </h3>
    </RouterLink>
  </article>
</template>

<style scoped>
.programme-card {
  position: relative;
  min-width: 0;
}
.programme-cover {
  position: relative;
  display: block;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  border-radius: var(--radius);
  border: 1px solid var(--line);
  background: var(--subtle);
  transition: border-color var(--motion-fast) var(--motion-ease);
}
.programme-image {
  height: 100%;
}
.cover-open {
  position: absolute;
  right: 9px;
  bottom: 9px;
  display: grid;
  width: 30px;
  height: 30px;
  place-items: center;
  border-radius: var(--radius-sm);
  border: 1px solid #ffffff33;
  background: color-mix(in srgb, var(--rail) 78%, transparent);
  backdrop-filter: blur(6px);
  color: #fff;
  opacity: 0;
  transform: translateY(2px);
  transition:
    opacity var(--motion-normal) var(--motion-ease),
    background-color var(--motion-fast) var(--motion-ease),
    transform var(--motion-normal) var(--motion-ease);
}
.favourite-button {
  position: absolute;
  top: 9px;
  right: 9px;
  display: grid;
  width: 34px;
  height: 34px;
  place-items: center;
  border-radius: var(--radius-sm);
  border: 1px solid #ffffff5c;
  backdrop-filter: blur(6px);
  background: color-mix(in srgb, var(--rail) 62%, transparent);
  color: #fff;
  transition:
    color var(--motion-fast) var(--motion-ease),
    background-color var(--motion-fast) var(--motion-ease),
    border-color var(--motion-fast) var(--motion-ease),
    transform var(--motion-fast) var(--motion-ease);
}
.favourite-button.saved {
  border-color: var(--accent);
  background: var(--accent);
  color: #fff;
  transform: rotate(-3deg);
}
.favourite-button.saved :deep(svg) {
  animation: favourite-pop 220ms var(--motion-ease);
}
.programme-caption {
  display: block;
  padding: 10px 2px 0;
}
.programme-name {
  display: -webkit-box;
  overflow: hidden;
  font-size: 16px;
  line-height: 1.45;
  font-weight: 600;
  overflow-wrap: anywhere;
  transition: color var(--motion-fast) var(--motion-ease);
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}
@media (hover: hover) {
  .programme-cover:hover {
    border-color: color-mix(in srgb, var(--accent) 45%, var(--line));
  }
  .programme-cover:hover .cover-open {
    opacity: 1;
    transform: none;
  }
  .cover-open:hover {
    background: var(--accent-fill);
  }
  .programme-cover:hover :deep(.cover-photo) {
    transform: scale(1.025);
  }
  .programme-card:hover .programme-name {
    color: var(--accent);
  }
  .favourite-button:hover {
    border-color: #fff;
    background: #fff;
    color: var(--accent);
  }
}
@media (width < 760px) {
  .favourite-button {
    top: 7px;
    right: 7px;
    width: 44px;
    height: 44px;
  }
  .programme-caption {
    padding-top: 8px;
  }
}
</style>

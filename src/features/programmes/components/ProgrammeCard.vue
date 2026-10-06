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
        :src="programme.cover"
        :alt="programme.name"
      />
      <span class="cover-open"><ArrowUpRight :size="20" /></span>
    </RouterLink>

    <button
      :class="['favourite-button', { saved: favourite }]"
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
        <h3>{{ programme.name }}</h3>
      </div>
      <ArrowUpRight :size="18" />
    </RouterLink>
  </article>
</template>

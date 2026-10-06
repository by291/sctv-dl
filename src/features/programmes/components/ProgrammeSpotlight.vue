<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { NButton } from 'naive-ui'
import { ArrowRight, Shuffle } from '@lucide/vue'

import CoverImage from '../../../components/CoverImage.vue'

import type { Programme } from '../types'

defineProps<{
  programme: Programme
  canChange: boolean
}>()

const emit = defineEmits<{
  change: []
}>()
</script>

<template>
  <section
    class="featured-card"
    aria-label="栏目探索"
  >
    <div class="featured-copy">
      <span class="feature-label">
        <span aria-hidden="true" />
        栏目探索
      </span>
      <h2 :key="programme.id">{{ programme.name }}</h2>
      <p>
        浏览播出日历，选择整期或精彩片段。
        <br />
        让每次回看，都触手可及。
      </p>
      <div class="feature-actions">
        <RouterLink
          :to="`/programmes/${programme.id}`"
          class="feature-link"
        >
          查看节目
          <ArrowRight :size="17" />
        </RouterLink>
        <NButton
          text
          :disabled="!canChange"
          aria-label="换一个栏目"
          @click="emit('change')"
        >
          <template #icon><Shuffle :size="16" /></template>
          换一个
        </NButton>
      </div>
    </div>
    <RouterLink
      :to="`/programmes/${programme.id}`"
      class="featured-visual"
      :aria-label="`查看${programme.name}`"
    >
      <CoverImage
        :key="programme.id"
        :src="programme.cover"
        :alt="programme.name"
      />
    </RouterLink>
    <span
      class="feature-orbit orbit-one"
      aria-hidden="true"
    />
    <span
      class="feature-orbit orbit-two"
      aria-hidden="true"
    />
  </section>
</template>

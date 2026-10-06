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
      <span class="feature-label flex items-center gap-[6px] text-meta text-[#ad6e5f]">
        <span
          class="size-[5px] rounded-full bg-current"
          aria-hidden="true"
        />
        栏目探索
      </span>
      <h2
        :key="programme.id"
        class="featured-title"
      >
        {{ programme.name }}
      </h2>
      <p class="text-meta leading-[1.8] text-muted max-[440px]:mt-[22px]">
        浏览播出日历，选择整期或精彩片段。
        <br />
        让每次回看，都触手可及。
      </p>
      <div class="feature-actions mt-[19px] flex flex-wrap items-center gap-6">
        <RouterLink
          :to="`/programmes/${programme.id}`"
          class="feature-link inline-flex items-center gap-[19px] text-body font-semibold text-[#b75241]"
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
        class="aspect-[16/10] animate-content-reveal"
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

<style scoped>
@reference '../../../styles/global.css';

@layer components {
  .featured-card {
    @apply relative flex min-h-[240px] overflow-clip rounded-xl bg-hero transition-shadow duration-200;
    @apply ease-[ease] hover:shadow-[0_8px_25px_#0000000c];
  }

  .featured-copy {
    @apply relative z-2 min-w-0 flex-1 px-7 py-[29px];

    @variant max-[1250px] {
      @apply pl-6;
    }

    @variant max-[760px] {
      @apply px-[22px] py-[26px];
    }

    @variant max-[440px] {
      @apply pl-5;
    }
  }

  .featured-title {
    @apply mt-3 mb-[9px] animate-content-reveal text-[26px] font-bold tracking-[-0.5px];
    @apply [overflow-wrap:anywhere];

    @variant max-[1250px] {
      @apply text-[23px];
    }

    @variant max-[440px] {
      @apply max-w-[60%] text-[21px];
    }
  }

  .featured-visual {
    @apply relative z-2 mr-6 w-[42%] max-w-[280px] shrink-0 -rotate-5 self-center overflow-hidden;
    @apply rounded-[10px] border-4 border-[#ffffff90] shadow-[0_16px_26px_#5e433524];

    @variant max-[1250px] {
      @apply mr-5 w-[38%];
    }

    @variant max-[760px] {
      @apply w-[40%];
    }

    @variant max-[440px] {
      @apply absolute top-7 right-5 mr-0 w-[32%];
    }
  }

  .feature-orbit {
    @apply pointer-events-none absolute rounded-full border border-[#cdad9c38];
  }

  .orbit-one {
    @apply -top-[44px] -right-[10px] size-[330px];
  }

  .orbit-two {
    @apply -top-[90px] -right-[58px] size-[420px];
  }
}
</style>

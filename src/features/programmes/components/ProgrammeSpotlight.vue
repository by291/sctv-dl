<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { NButton } from 'naive-ui'
import { ArrowRight, Shuffle } from '@lucide/vue'

import CoverImage from '@/shared/components/CoverImage.vue'
import { useProgrammeCoverNavigation } from '@/features/programmes/composables/useProgrammeCoverNavigation'

import type { Programme } from '@/features/programmes/model/programme'

const props = defineProps<{
  programme: Programme
  canChange: boolean
}>()

const emit = defineEmits<{
  change: []
}>()

const { coverStyle, openProgramme } = useProgrammeCoverNavigation(() => props.programme.id)
</script>

<template>
  <section
    class="featured-card"
    aria-label="栏目探索"
  >
    <div class="featured-copy">
      <span class="feature-label">
        <span
          class="feature-dot"
          aria-hidden="true"
        />
        栏目探索
      </span>
      <h2
        :key="programme.id"
        class="featured-title"
        :title="programme.name"
      >
        {{ programme.name }}
      </h2>
      <p class="feature-description">
        浏览播出日历，选择整期或精彩片段。
        <br />
        让每次回看，都触手可及。
      </p>
      <div class="feature-actions">
        <RouterLink
          :to="`/programmes/${programme.id}`"
          class="feature-link"
          @click.capture="openProgramme"
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
      @click.capture="openProgramme"
    >
      <CoverImage
        :key="programme.id"
        class="featured-image"
        :style="coverStyle"
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
.featured-card {
  position: relative;
  display: flex;
  min-height: 240px;
  overflow: clip;
  border-radius: 12px;
  background: var(--hero);
  transition: box-shadow 200ms ease;
}
.featured-copy {
  position: relative;
  z-index: 2;
  min-width: 0;
  flex: 1;
  padding: 29px 28px;
}
.feature-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 14px;
  color: var(--hero-label);
}
.feature-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: currentColor;
}
.featured-title {
  display: -webkit-box;
  overflow: hidden;
  margin: 12px 0 9px;
  font-size: 26px;
  font-weight: 700;
  letter-spacing: -0.5px;
  overflow-wrap: anywhere;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  animation: content-reveal var(--motion-normal) var(--motion-ease);
}
.feature-description {
  font-size: 14px;
  line-height: 1.8;
  color: var(--muted);
}
.feature-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 24px;
  margin-top: 19px;
}
.feature-link {
  display: inline-flex;
  align-items: center;
  gap: 19px;
  font-size: 16px;
  font-weight: 600;
  color: var(--hero-link);
}
.featured-visual {
  position: relative;
  z-index: 2;
  margin-right: 24px;
  width: 42%;
  max-width: 280px;
  flex-shrink: 0;
  rotate: -5deg;
  align-self: center;
  overflow: hidden;
  border-radius: 10px;
  border: 4px solid #ffffff90;
  box-shadow: 0 16px 26px #5e433524;
}
.featured-image {
  aspect-ratio: 16 / 10;
  animation: content-reveal var(--motion-normal) var(--motion-ease);
}
.feature-orbit {
  pointer-events: none;
  position: absolute;
  border-radius: 50%;
  border: 1px solid #cdad9c38;
}
.orbit-one {
  top: -44px;
  right: -10px;
  width: 330px;
  height: 330px;
}
.orbit-two {
  top: -90px;
  right: -58px;
  width: 420px;
  height: 420px;
}
@media (hover: hover) {
  .featured-card:hover {
    box-shadow: 0 8px 25px #0000000c;
  }
}
@media (width < 1250px) {
  .featured-copy {
    padding-left: 24px;
  }
  .featured-title {
    font-size: 23px;
  }
  .featured-visual {
    margin-right: 20px;
    width: 38%;
  }
}
@media (width < 760px) {
  .featured-card {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 96px;
    min-height: 0;
    gap: 4px 16px;
    padding: 16px;
  }
  .featured-copy {
    display: contents;
  }
  .feature-label,
  .featured-title {
    grid-column: 1;
  }
  .featured-title {
    margin: 0;
    font-size: 20px;
  }
  .feature-description {
    display: none;
  }
  .feature-actions {
    grid-column: 1 / -1;
    gap: 20px;
    margin-top: 4px;
  }
  .feature-link {
    min-height: 44px;
    gap: 10px;
  }
  .feature-actions :deep(.n-button) {
    min-height: 44px;
  }
  .featured-visual {
    grid-column: 2;
    grid-row: 1 / span 2;
    margin: 0;
    width: 96px;
    rotate: none;
    border-width: 2px;
  }
}
</style>

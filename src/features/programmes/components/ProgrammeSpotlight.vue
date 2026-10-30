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

const shuffleTheme = {
  textColorText: 'var(--hero-text)',
  textColorTextHover: 'var(--hero-text)',
  textColorTextPressed: 'var(--hero-text)',
  textColorTextFocus: 'var(--hero-text)',
  fontSizeMedium: '14px',
  heightMedium: '40px',
}

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
      <p class="feature-description">浏览播出日历，回看或下载整期节目与精彩片段。</p>
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
          :theme-overrides="shuffleTheme"
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
  </section>
</template>

<style scoped>
.featured-card {
  --focus: var(--hero-text);

  position: relative;
  display: flex;
  align-items: center;
  gap: clamp(24px, 4vw, 56px);
  min-height: 248px;
  overflow: clip;
  border-radius: 8px;
  background: var(--hero);
  padding: clamp(24px, 3.2vw, 40px);
}
.featured-copy {
  position: relative;
  z-index: 2;
  min-width: 0;
  flex: 1;
}
.feature-label {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  font-weight: 500;
  color: var(--hero-label);
}
.feature-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--accent);
  box-shadow: 0 0 0 4px color-mix(in srgb, var(--accent) 22%, transparent);
}
.featured-title {
  display: -webkit-box;
  overflow: hidden;
  margin: 13px 0 10px;
  font-size: clamp(30px, 3.6cqw, 44px);
  line-height: 1.15;
  font-weight: 800;
  letter-spacing: -0.6px;
  color: var(--hero-text);
  overflow-wrap: anywhere;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  animation: content-reveal var(--motion-normal) var(--motion-ease);
}
.feature-description {
  max-width: 42ch;
  font-size: 15px;
  line-height: 1.8;
  color: var(--hero-muted);
}
.feature-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 18px;
  margin-top: 24px;
}
.feature-link {
  display: inline-flex;
  min-height: 42px;
  align-items: center;
  gap: 10px;
  border-radius: 5px;
  background: var(--accent-fill);
  padding: 0 18px;
  font-size: 15px;
  font-weight: 600;
  color: #fff;
  transition: background-color var(--motion-fast) var(--motion-ease);
}
.feature-link svg {
  transition: transform var(--motion-normal) var(--motion-ease);
}
.featured-visual {
  position: relative;
  z-index: 2;
  width: clamp(240px, 34%, 380px);
  aspect-ratio: 16 / 9;
  flex-shrink: 0;
  overflow: hidden;
  border-radius: var(--radius);
  border: 1px solid var(--hero-line);
  box-shadow: 0 24px 48px #0000003d;
}
.featured-image {
  height: 100%;
  animation: content-reveal var(--motion-normal) var(--motion-ease);
}
@media (hover: hover) {
  .feature-link:hover {
    background: var(--accent-fill-hover);
  }
  .feature-link:hover svg {
    transform: translateX(3px);
  }
  .featured-visual:hover :deep(.cover-photo) {
    transform: scale(1.02);
  }
}
@container workspace (width < 860px) {
  .featured-card {
    gap: 28px;
  }
  .featured-title {
    font-size: clamp(26px, 4cqw, 34px);
  }
  .featured-visual {
    width: clamp(200px, 34%, 300px);
  }
}
@container workspace (width < 620px) {
  .featured-card {
    display: grid;
    grid-template-columns: minmax(0, 1fr) clamp(96px, 26cqw, 150px);
    align-items: center;
    gap: 4px 16px;
    min-height: 0;
    padding: 18px;
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
    font-size: 22px;
    line-height: 1.25;
  }
  .feature-description {
    display: none;
  }
  .feature-actions {
    grid-column: 1 / -1;
    gap: 16px;
    margin-top: 12px;
  }
  .feature-link {
    min-height: 44px;
    padding-inline: 16px;
    font-size: 14px;
  }
  .feature-actions :deep(.n-button) {
    min-height: 44px;
  }
  .featured-visual {
    grid-column: 2;
    grid-row: 1 / span 2;
    width: 100%;
  }
}
</style>

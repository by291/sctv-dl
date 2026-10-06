<script setup lang="ts">
import '../styles.css'
import { computed, onMounted, ref } from 'vue'

import { RouterLink } from 'vue-router'
import { NButton, NInput, NSelect } from 'naive-ui'
import { Search, RefreshCw, ArrowRight, Tv, CalendarDays } from '@lucide/vue'

import { useProgrammeStore } from '../store'
import { useSettingsStore } from '../../settings/store'
import CoverImage from '../../../components/CoverImage.vue'
import StatePanel from '../../../components/StatePanel.vue'
import ProgrammeCard from '../components/ProgrammeCard.vue'

const store = useProgrammeStore()
const settings = useSettingsStore()
const query = ref('')
const tab = ref<'all' | 'favourites'>('all')
const sort = ref('default')

const sortOptions = [
  { label: '默认排序', value: 'default' },
  { label: '按名称排序', value: 'name' },
]
const filtered = computed(() => {
  const items = store.programmes.filter(
    (item) =>
      item.name.toLowerCase().includes(query.value.trim().toLowerCase()) &&
      (tab.value === 'all' || settings.favourites.includes(item.id)),
  )

  return sort.value === 'name'
    ? [...items].sort((a, b) => a.name.localeCompare(b.name, 'zh-CN'))
    : items
})
const featured = computed(
  () => store.programmes.find((item) => item.id === '1') || store.programmes[0],
)
onMounted(() => {
  void store.load()
})
</script>

<template>
  <section class="page-heading">
    <div>
      <div class="eyebrow">PROGRAMME LIBRARY</div>
      <h1>
        发现节目，收藏日常
        <span class="title-dot">.</span>
      </h1>
      <p>从四川出发，把每一期值得回看的节目留在身边。</p>
    </div>
    <NButton
      :loading="store.loading"
      secondary
      @click="store.load(true)"
    >
      <template #icon><RefreshCw :size="16" /></template>
      刷新节目
    </NButton>
  </section>

  <div
    v-if="featured"
    class="library-intro"
  >
    <RouterLink
      :to="`/programmes/${featured.id}`"
      class="featured-card"
    >
      <div class="featured-copy">
        <span class="feature-label">
          <span />
          从这里开始
        </span>
        <h2>{{ featured.name }}</h2>
        <p>
          浏览播出日历，选择整期或精彩片段。
          <br />
          让每次回看，都触手可及。
        </p>
        <span class="feature-link">
          查看节目
          <ArrowRight :size="17" />
        </span>
      </div>
      <div class="featured-visual">
        <CoverImage
          :src="featured.cover"
          :alt="featured.name"
        />
      </div>
      <span class="feature-orbit orbit-one" />
      <span class="feature-orbit orbit-two" />
    </RouterLink>
    <div class="library-stat">
      <span class="stat-icon">
        <Tv
          :size="23"
          :stroke-width="1.5"
        />
      </span>
      <div class="stat-number">
        {{ store.programmes.length }}
        <span>个栏目</span>
      </div>
      <h3>属于你的节目库</h3>
      <p>
        按日期发现整期与片段
        <br />
        收藏常看的栏目，随时回来
      </p>
      <div class="stat-foot">
        <CalendarDays :size="15" />
        往期节目 · 随时回看
      </div>
    </div>
  </div>

  <div class="library-toolbar">
    <div
      class="tabs"
      role="tablist"
      aria-label="栏目筛选"
    >
      <button
        :class="{ selected: tab === 'all' }"
        role="tab"
        :aria-selected="tab === 'all'"
        @click="tab = 'all'"
      >
        全部栏目
        <span>{{ store.programmes.length }}</span>
      </button>
      <button
        :class="{ selected: tab === 'favourites' }"
        role="tab"
        :aria-selected="tab === 'favourites'"
        @click="tab = 'favourites'"
      >
        我的收藏
        <span>{{ settings.favourites.length }}</span>
      </button>
    </div>
    <div class="library-filters">
      <NInput
        v-model:value="query"
        clearable
        placeholder="搜索节目名称"
        aria-label="搜索节目名称"
      >
        <template #prefix><Search :size="17" /></template>
      </NInput>
      <NSelect
        v-model:value="sort"
        :options="sortOptions"
        aria-label="节目排序"
      />
    </div>
  </div>

  <StatePanel
    v-if="store.loading && !store.programmes.length"
    loading
  />

  <StatePanel
    v-else-if="store.error"
    :error="store.error"
    @retry="store.load(true)"
  />

  <StatePanel
    v-else-if="!filtered.length"
    :title="tab === 'favourites' && !query ? '收藏你常看的节目' : '没有找到匹配的栏目'"
    :description="
      tab === 'favourites' && !query
        ? '点击栏目右上角的星标，下次就能在这里快速找到。'
        : '换一个关键词试试，或清空搜索查看全部栏目。'
    "
  />

  <div
    v-else
    class="programme-grid"
  >
    <ProgrammeCard
      v-for="programme in filtered"
      :key="programme.id"
      :programme="programme"
      :favourite="settings.favourites.includes(programme.id)"
      @toggle-favourite="settings.toggleFavourite"
    />
  </div>

  <div
    v-if="filtered.length"
    class="list-footer"
  >
    <span>共 {{ filtered.length }} 个栏目</span>
    <span>内容来自四川观察节目服务</span>
  </div>
</template>

<script setup lang="ts">
import '../styles.css'
import { computed, onMounted, ref } from 'vue'

import { RouterLink } from 'vue-router'
import { NButton, NInput, NSelect } from 'naive-ui'
import { Search, RefreshCw, ArrowRight } from '@lucide/vue'

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
      <h1>节目库</h1>
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
          <span aria-hidden="true" />
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
      <span
        class="feature-orbit orbit-one"
        aria-hidden="true"
      />
      <span
        class="feature-orbit orbit-two"
        aria-hidden="true"
      />
    </RouterLink>
    <div class="library-stat">
      <h2>节目概览</h2>
      <div class="library-stat-row">
        <span>全部栏目</span>
        <strong>{{ store.programmes.length }}</strong>
      </div>
      <div class="library-stat-row">
        <span>已收藏</span>
        <strong>{{ settings.favourites.length }}</strong>
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
    :title="tab === 'favourites' && !query ? '暂无收藏栏目' : '没有找到匹配的栏目'"
    :description="
      tab === 'favourites' && !query ? '点击栏目右上角的星标添加收藏。' : '请更换关键词或清空搜索。'
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

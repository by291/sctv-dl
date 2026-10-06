<script setup lang="ts">
import '../styles.css'
import { computed, onMounted, ref, toRef } from 'vue'

import { NButton, NInput, NSelect } from 'naive-ui'
import { Search, RefreshCw } from '@lucide/vue'

import { useProgrammeStore } from '../store'
import { useSettingsStore } from '../../settings/store'
import StatePanel from '../../../components/StatePanel.vue'
import ProgrammeCard from '../components/ProgrammeCard.vue'
import ProgrammeSpotlight from '../components/ProgrammeSpotlight.vue'
import { useFeaturedProgramme } from '../composables/useFeaturedProgramme'

const store = useProgrammeStore()
const settings = useSettingsStore()
const query = ref('')
const tab = ref<'all' | 'favourites'>('all')
const sort = ref<'default' | 'name'>('default')

const sortOptions = [
  { label: '默认排序', value: 'default' },
  { label: '按名称排序', value: 'name' },
]
const filtered = computed(() => {
  const favourites = new Set(settings.favourites)
  const search = query.value.trim().toLowerCase()
  const items = store.programmes.filter(
    (item) =>
      item.name.toLowerCase().includes(search) && (tab.value === 'all' || favourites.has(item.id)),
  )

  return items.sort((a, b) => {
    const priority = Number(favourites.has(b.id)) - Number(favourites.has(a.id))

    // Stable sorting preserves the service order within each group in default mode.
    return priority || (sort.value === 'name' ? a.name.localeCompare(b.name, 'zh-CN') : 0)
  })
})
const { featured, canChange, chooseAnother } = useFeaturedProgramme(toRef(store, 'programmes'))

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
    <ProgrammeSpotlight
      :programme="featured"
      :can-change="canChange"
      @change="chooseAnother"
    />
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

  <TransitionGroup
    v-else
    name="catalogue"
    tag="div"
    class="programme-grid"
  >
    <ProgrammeCard
      v-for="programme in filtered"
      :key="programme.id"
      :programme="programme"
      :favourite="settings.favourites.includes(programme.id)"
      @toggle-favourite="settings.toggleFavourite"
    />
  </TransitionGroup>

  <div
    v-if="filtered.length"
    class="list-footer"
  >
    <span>共 {{ filtered.length }} 个栏目</span>
    <span>内容来自四川观察节目服务</span>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, toRef } from 'vue'

import { NButton, NInput, NSelect, NTab, NTabs } from 'naive-ui'
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
const tabTheme = {
  tabTextColorLine: 'var(--muted)',
  tabTextColorActiveLine: 'var(--text)',
  tabTextColorHoverLine: 'var(--text)',
  tabFontWeightActive: '600',
  tabFontSizeMedium: '16px',
  tabGapMediumLine: '24px',
  tabPaddingMediumLine: 'var(--library-tab-padding)',
  tabBorderColor: 'var(--line)',
}

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
      <h2 class="library-stat-heading">节目概览</h2>
      <div class="library-stat-row">
        <span>全部栏目</span>
        <strong class="library-stat-value">{{ store.programmes.length }}</strong>
      </div>
      <div class="library-stat-row">
        <span>已收藏</span>
        <strong class="library-stat-value">{{ settings.favourites.length }}</strong>
      </div>
    </div>
  </div>

  <div class="library-toolbar">
    <NTabs
      v-model:value="tab"
      class="library-tabs"
      type="line"
      size="medium"
      :bar-width="32"
      :theme-overrides="tabTheme"
      role="tablist"
      aria-label="栏目筛选"
    >
      <NTab
        name="all"
        role="tab"
        tabindex="0"
        :aria-selected="tab === 'all'"
        @keydown.enter.prevent="tab = 'all'"
        @keydown.space.prevent="tab = 'all'"
      >
        全部栏目
        <span class="filter-count">
          {{ store.programmes.length }}
        </span>
      </NTab>
      <NTab
        name="favourites"
        role="tab"
        tabindex="0"
        :aria-selected="tab === 'favourites'"
        @keydown.enter.prevent="tab = 'favourites'"
        @keydown.space.prevent="tab = 'favourites'"
      >
        我的收藏
        <span class="filter-count">
          {{ settings.favourites.length }}
        </span>
      </NTab>
    </NTabs>
    <div class="library-filters">
      <NInput
        v-model:value="query"
        class="library-search"
        clearable
        placeholder="搜索节目名称"
        aria-label="搜索节目名称"
      >
        <template #prefix><Search :size="17" /></template>
      </NInput>
      <NSelect
        v-model:value="sort"
        class="library-sort"
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

<style scoped>
.library-tabs {
  --library-tab-padding: 9px 0 12px;
  margin-bottom: -1px;
  width: auto !important;
  flex-shrink: 0;
}
/* Keep badges outside the measured tab so the indicator centers on its text. */
.library-tabs :deep(.n-tabs-tab-wrapper) {
  padding-right: 36px;
}
.library-tabs :deep(.n-tabs-tab__label) {
  position: relative;
}
.library-tabs :deep(.n-tabs-tab:focus-visible) {
  outline: 3px solid #e99389;
  outline-offset: -3px;
}
.library-tabs :deep(.filter-count) {
  position: absolute;
  top: 50%;
  left: 100%;
  margin-left: 8px;
  translate: 0 -50%;
  border-radius: 5px;
  background: var(--subtle);
  padding: 2px 5px;
  font-size: 14px;
  font-weight: 500;
  color: var(--muted);
  transition:
    color 140ms ease,
    background-color 140ms ease;
}
.library-tabs :deep(.n-tabs-tab--active .filter-count) {
  background: var(--accent-soft);
  color: var(--accent);
}
.library-intro {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 242px;
  gap: 20px;
  margin-bottom: 31px;
}
.library-stat {
  border-radius: 12px;
  border: 1px solid var(--line);
  background: var(--panel);
  padding: 20px 24px;
}
.library-stat-heading {
  margin-bottom: 12px;
  font-size: 16px;
  font-weight: 700;
}
.library-stat-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding-block: 4px;
  font-size: 14px;
  color: var(--muted);
}
.library-stat-value {
  font-size: 22px;
  color: var(--text);
  font-variant-numeric: tabular-nums;
}
.library-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  margin-bottom: 22px;
  border-bottom: 1px solid var(--line);
}
.library-filters {
  display: flex;
  gap: 12px;
  margin-bottom: 3px;
}
.library-search {
  width: 200px !important;
}
.library-sort {
  width: 148px !important;
}
.programme-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  column-gap: 20px;
  row-gap: 22px;
}
.list-footer {
  display: flex;
  justify-content: space-between;
  padding-top: 25px;
  font-size: 14px;
  color: var(--muted);
}
@media (width >= 1700px) {
  .programme-grid {
    grid-template-columns: repeat(5, minmax(0, 1fr));
  }
}
@media (width < 1250px) {
  .library-intro {
    grid-template-columns: minmax(0, 1fr) 210px;
  }
  .library-stat {
    padding-inline: 20px;
  }
  .programme-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}
@media (width < 1020px) {
  .library-tabs {
    --library-tab-padding: 9px 0 10px;
    width: 100% !important;
  }
  .library-stat {
    display: none;
  }
  .library-intro {
    grid-template-columns: minmax(0, 1fr);
  }
  .library-toolbar {
    flex-direction: column;
    align-items: flex-start;
    gap: 16px;
    border: 0;
  }
  .library-filters {
    margin-bottom: 0;
    width: 100%;
  }
  .library-search {
    flex: 1;
  }
  .programme-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
@media (width < 760px) {
  .library-intro {
    margin-bottom: 25px;
  }
  .programme-grid {
    column-gap: 14px;
    row-gap: 18px;
  }
}
</style>

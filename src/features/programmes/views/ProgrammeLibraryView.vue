<script setup lang="ts">
import { computed, nextTick, onActivated, onMounted, ref, toRef } from 'vue'
import { onBeforeRouteLeave } from 'vue-router'

import { NButton, NInput, NSelect, NTab, NTabs } from 'naive-ui'
import { Search, RefreshCw } from '@lucide/vue'

import { useProgrammeCatalogueStore } from '@/features/programmes/stores/useProgrammeCatalogueStore'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'
import StatePanel from '@/shared/components/StatePanel.vue'
import ProgrammeCard from '@/features/programmes/components/ProgrammeCard.vue'
import ProgrammeSpotlight from '@/features/programmes/components/ProgrammeSpotlight.vue'
import { useFeaturedProgramme } from '@/features/programmes/composables/useFeaturedProgramme'
import ProgrammeUpdateNotice from '@/features/programmes/components/ProgrammeUpdateNotice.vue'
import { usePageScroll } from '@/shared/navigation/page-scroll'

const { pageScrollPosition, scrollPageTo } = usePageScroll()

const store = useProgrammeCatalogueStore()
const settings = useSettingsStore()

const query = ref('')
const tab = ref<'all' | 'favourites'>('all')
const sort = ref<'default' | 'name'>('default')
// Keep card positions stable while favourites change; a page reload starts a new session.
const favouritePriority = new Set(settings.favourites)
let scrollPosition = { left: 0, top: 0 }

const sortOptions = [
  { label: '默认排序', value: 'default' },
  { label: '按名称排序', value: 'name' },
]
const tabTheme = {
  tabTextColorLine: 'var(--muted)',
  tabTextColorActiveLine: 'var(--text)',
  tabTextColorHoverLine: 'var(--text)',
  barColor: 'var(--accent)',
  tabFontWeightActive: '600',
  tabFontSizeMedium: '15px',
  tabGapMediumLine: '26px',
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
    const priority =
      tab.value === 'all'
        ? Number(favouritePriority.has(b.id)) - Number(favouritePriority.has(a.id))
        : 0

    // Stable sorting preserves the service order within each group in default mode.
    return priority || (sort.value === 'name' ? a.name.localeCompare(b.name, 'zh-CN') : 0)
  })
})
const emptyState = computed(() => {
  const emptyFavourites = tab.value === 'favourites' && !query.value

  return {
    title: emptyFavourites ? '暂无收藏栏目' : '没有找到匹配的栏目',
    description: emptyFavourites ? '点击栏目右上角的星标添加收藏。' : '请更换关键词或清空搜索。',
  }
})

const { featured, canChange, chooseAnother } = useFeaturedProgramme(toRef(store, 'programmes'))

onMounted(() => {
  void store.load()
})

onBeforeRouteLeave(() => {
  scrollPosition = pageScrollPosition()
})

onActivated(async () => {
  if (store.fetchedAt && !store.refreshing) {
    void store.load(true)
  }

  await nextTick()
  scrollPageTo(scrollPosition)
})
</script>

<template>
  <div class="library-view">
    <section class="page-heading">
      <div>
        <h1>节目库</h1>
      </div>
      <NButton
        :loading="store.refreshing"
        secondary
        @click="store.load(true)"
      >
        <template #icon><RefreshCw :size="16" /></template>
        刷新节目
      </NButton>
    </section>

    <ProgrammeUpdateNotice
      :pending="store.pendingUpdate"
      :cached="store.cached"
      :fetched-at="store.fetchedAt"
      :refresh-error="store.refreshError"
      :cache-warning="store.cacheWarning"
      @accept="store.acceptUpdate"
      @retry="store.load(true)"
    />

    <div
      v-if="featured"
      class="library-intro"
    >
      <ProgrammeSpotlight
        :programme="featured"
        :can-change="canChange"
        @change="chooseAnother"
      />
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
      :title="emptyState.title"
      :description="emptyState.description"
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
  outline: 2px solid var(--focus);
  outline-offset: -3px;
}
.library-tabs .filter-count {
  position: absolute;
  top: 50%;
  left: 100%;
  margin-left: 7px;
  translate: 0 -50%;
  border-radius: var(--radius-sm);
  background: var(--subtle);
  padding: 1px 6px;
  font-size: 12px;
  font-weight: 500;
  color: var(--muted);
  transition:
    color var(--motion-fast) var(--motion-ease),
    background-color var(--motion-fast) var(--motion-ease);
}
.library-tabs :deep(.n-tabs-tab--active) .filter-count {
  background: var(--accent-soft);
  color: var(--accent);
}
.library-intro {
  margin-bottom: 30px;
}
.library-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  margin-bottom: 24px;
  border-bottom: 1px solid var(--line);
}
.library-filters {
  display: flex;
  gap: 10px;
  margin-bottom: 3px;
}
.library-search {
  width: 224px !important;
}
.library-sort {
  width: 144px !important;
}
.programme-grid {
  display: grid;
  /* Keep filtered results at the same thumbnail size as the complete catalogue. */
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 212px), 1fr));
  column-gap: 22px;
  row-gap: 26px;
}
.list-footer {
  display: flex;
  justify-content: space-between;
  margin-top: 32px;
  border-top: 1px solid var(--line);
  padding-top: 16px;
  font-size: 13px;
  color: var(--muted);
}
@container workspace (width < 720px) {
  .library-tabs {
    --library-tab-padding: 9px 0 10px;
    width: 100% !important;
  }
  .library-toolbar {
    flex-direction: column;
    align-items: flex-start;
    gap: 14px;
    border: 0;
  }
  .library-filters {
    margin-bottom: 0;
    width: 100%;
  }
  .library-search {
    flex: 1;
  }
}
@media (width < 760px) {
  .library-intro {
    margin-bottom: 22px;
  }
  .library-filters {
    gap: 8px;
  }
  .library-search {
    min-width: 0;
    width: auto !important;
  }
  .library-sort {
    width: 132px !important;
  }
  .programme-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 18px 12px;
  }
  .list-footer {
    flex-direction: column;
    gap: 4px;
    margin-top: 24px;
    padding-top: 14px;
  }
}
</style>

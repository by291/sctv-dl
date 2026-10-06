<script setup lang="ts">
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
    <div
      class="library-stat rounded-xl border border-line bg-panel px-6 py-5 max-[1250px]:px-5 max-[1020px]:hidden"
    >
      <h2 class="mb-3 text-body font-bold">节目概览</h2>
      <div
        class="library-stat-row flex items-center justify-between gap-4 py-1 text-meta text-muted"
      >
        <span>全部栏目</span>
        <strong class="text-[22px] text-main tabular-nums">{{ store.programmes.length }}</strong>
      </div>
      <div
        class="library-stat-row flex items-center justify-between gap-4 py-1 text-meta text-muted"
      >
        <span>已收藏</span>
        <strong class="text-[22px] text-main tabular-nums">{{ settings.favourites.length }}</strong>
      </div>
    </div>
  </div>

  <div class="library-toolbar">
    <div
      class="tabs flex items-center gap-6"
      role="tablist"
      aria-label="栏目筛选"
    >
      <button
        class="filter-tab library-tab"
        :class="{ selected: tab === 'all' }"
        role="tab"
        :aria-selected="tab === 'all'"
        @click="tab = 'all'"
      >
        全部栏目
        <span class="filter-count">
          {{ store.programmes.length }}
        </span>
      </button>
      <button
        class="filter-tab library-tab"
        :class="{ selected: tab === 'favourites' }"
        role="tab"
        :aria-selected="tab === 'favourites'"
        @click="tab = 'favourites'"
      >
        我的收藏
        <span class="filter-count">
          {{ settings.favourites.length }}
        </span>
      </button>
    </div>
    <div class="library-filters flex gap-3 max-[1020px]:w-full">
      <NInput
        v-model:value="query"
        class="w-50! max-[1020px]:flex-1"
        clearable
        placeholder="搜索节目名称"
        aria-label="搜索节目名称"
      >
        <template #prefix><Search :size="17" /></template>
      </NInput>
      <NSelect
        v-model:value="sort"
        class="w-37!"
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
    class="list-footer flex justify-between pt-6.25 text-meta text-muted"
  >
    <span>共 {{ filtered.length }} 个栏目</span>
    <span>内容来自四川观察节目服务</span>
  </div>
</template>

<style scoped>
@reference '../../../styles/global.css';

@layer components {
  .library-tab::after {
    @apply -bottom-4;

    @variant max-[1020px] {
      @apply -bottom-2.5;
    }
  }

  .library-intro {
    @apply mb-7.75 grid grid-cols-[minmax(0,1fr)_242px] gap-5;

    @variant max-[1250px] {
      @apply grid-cols-[minmax(0,1fr)_210px];
    }

    @variant max-[1020px] {
      @apply grid-cols-1;
    }

    @variant max-[760px] {
      @apply mb-6.25;
    }
  }

  .library-toolbar {
    @apply mb-5.5 flex items-center justify-between gap-5 border-b border-line pb-3.75;

    @variant max-[1020px] {
      @apply flex-col items-start gap-7;
    }
  }

  .programme-grid {
    @apply grid grid-cols-4 gap-x-5 gap-y-5.5;

    @variant min-[1700px] {
      @apply grid-cols-5;
    }

    @variant max-[1250px] {
      @apply grid-cols-3;
    }

    @variant max-[1020px] {
      @apply grid-cols-2;
    }

    @variant max-[760px] {
      @apply gap-x-3.5 gap-y-4.5;
    }
  }
}
</style>

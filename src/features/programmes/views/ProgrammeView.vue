<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'

import { RouterLink } from 'vue-router'
import { NButton, NCheckbox, useMessage } from 'naive-ui'
import { ArrowLeft, CalendarDays, Star, Check } from '@lucide/vue'

import { errorMessage } from '../../../shared/errors'
import { makeDownloadTask } from '../../downloads/model'
import { useDownloadStore } from '../../downloads/store'
import { useSettingsStore } from '../../settings/store'
import { useProgrammeStore } from '../store'
import { useProgrammeArchive } from '../composables/useProgrammeArchive'
import { useContentSelection } from '../composables/useContentSelection'
import CoverImage from '../../../components/CoverImage.vue'
import StatePanel from '../../../components/StatePanel.vue'
import ProgrammeDatePicker from '../components/ProgrammeDatePicker.vue'
import ProgrammeContentList from '../components/ProgrammeContentList.vue'
import ProgrammePreviewDialog from '../components/ProgrammePreviewDialog.vue'
import ProgrammeDownloadButton from '../components/ProgrammeDownloadButton.vue'

import type { ProgrammeContent, Quality } from '../types'

const props = defineProps<{ id: string }>()
const catalogue = useProgrammeStore()
const downloads = useDownloadStore()
const settings = useSettingsStore()
const message = useMessage()

const programmeId = computed(() => props.id)
const programme = computed(() => catalogue.programmes.find((item) => item.id === programmeId.value))
const programmeName = computed(() => programme.value?.name ?? '')
const {
  dates,
  selectedDate,
  contents,
  loadingDates,
  loadingContents,
  dateError,
  contentError,
  loadDates,
  loadContents,
} = useProgrammeArchive(programmeId)
const { selected, allSelected, fullIds, selectAll, selectFullEpisodes } = useContentSelection(
  contents,
  programmeName,
  selectedDate,
)
const preview = ref<ProgrammeContent | null>(null)
const selectedContents = computed(() =>
  contents.value.filter((item) => selected.value.includes(item.id)),
)

const dateSummary = computed(() => {
  if (loadingDates.value) {
    return '播出日期加载中'
  }

  if (dateError.value) {
    return '播出日期暂不可用'
  }

  return dates.value.length ? `${dates.value.length.toLocaleString()} 个播出日期` : '暂无播出日期'
})

function openPreview(content: ProgrammeContent) {
  preview.value = content
}

function addDownloads(items: ProgrammeContent[], quality: Quality) {
  try {
    if (!items.length) {
      return
    }

    const tasks = items.map((item) =>
      makeDownloadTask(item, programmeName.value || '电视节目', selectedDate.value || '', quality),
    )
    const count = downloads.add(tasks)
    const fallback = tasks.some((task) => task.quality !== quality)
      ? `，缺少${quality === 'smooth' ? '流畅' : '标准'}版本的内容使用${quality === 'smooth' ? '标准' : '流畅'}画质`
      : ''

    message.success(count ? `已加入 ${count} 个下载任务${fallback}` : '所选内容已在下载列表中')
  } catch (cause) {
    message.error(errorMessage(cause))
  }
}

watch(contents, () => {
  preview.value = null
})

onMounted(() => {
  void catalogue.load()
})
</script>

<template>
  <RouterLink
    to="/"
    class="back-link mb-[25px] inline-flex items-center gap-[7px] text-meta text-muted hover:text-accent"
  >
    <ArrowLeft :size="16" />
    返回节目库
  </RouterLink>

  <section class="detail-heading">
    <div class="detail-cover">
      <CoverImage
        :src="programme?.cover || null"
        :alt="programmeName || '电视节目'"
      />
    </div>
    <div class="detail-copy flex-1">
      <h1 class="mt-[6px] text-[28px] max-[760px]:text-[23px]">
        {{ programmeName || '电视节目' }}
      </h1>
      <span
        class="detail-meta mt-[13px] flex flex-wrap items-center gap-[7px] text-meta text-muted max-[760px]:leading-[1.5]"
      >
        <CalendarDays :size="15" />
        <span class="whitespace-nowrap">{{ dateSummary }}</span>
        <span
          v-if="dates.length"
          class="whitespace-nowrap"
        >
          · {{ dates.at(-1)?.date }} 起
        </span>
      </span>
    </div>
    <NButton
      v-if="programme"
      class="max-[1020px]:self-start max-[760px]:ml-[126px]! max-[440px]:ml-[100px]!"
      secondary
      @click="settings.toggleFavourite(programme.id)"
    >
      <template #icon>
        <Star
          :size="16"
          :fill="settings.favourites.includes(programme.id) ? 'currentColor' : 'none'"
        />
      </template>
      {{ settings.favourites.includes(programme.id) ? '已收藏' : '收藏栏目' }}
    </NButton>
  </section>

  <div class="content-panel rounded-xl border border-line bg-panel">
    <ProgrammeDatePicker
      v-model="selectedDate"
      :dates="dates"
      :loading="loadingDates"
      @refresh="loadDates"
    />

    <StatePanel
      v-if="loadingDates"
      loading
    />
    <StatePanel
      v-else-if="dateError"
      title="播出日期加载失败"
      :error="dateError"
      @retry="loadDates"
    />
    <StatePanel
      v-else-if="!dates.length"
      title="这个栏目还没有可用的节目日期"
      description="稍后回来看看，或选择其他栏目。"
    />

    <template v-else>
      <div class="content-toolbar">
        <div
          class="content-count flex items-baseline gap-[13px] max-[1020px]:flex-wrap max-[1020px]:gap-[7px]"
        >
          <h2 class="text-[18px] leading-[1.5] font-semibold">{{ selectedDate }}</h2>
          <span class="content-kind text-body text-main">节目内容</span>
          <span
            v-if="!loadingContents && !contentError"
            class="text-meta text-muted"
          >
            {{ contents.length }} 条内容
          </span>
        </div>
        <ProgrammeDownloadButton
          v-if="!loadingContents && !contentError && contents.length"
          :contents="selectedContents"
          label="批量下载"
          primary
          @download="addDownloads(selectedContents, $event)"
        />
      </div>

      <StatePanel
        v-if="loadingContents"
        loading
      />
      <StatePanel
        v-else-if="contentError"
        title="节目内容加载失败"
        :error="contentError"
        @retry="loadContents"
      />
      <StatePanel
        v-else-if="!contents.length"
        title="这一天还没有节目内容"
        description="试试其他播出日期。"
      />

      <template v-else>
        <div class="selection-toolbar">
          <NCheckbox
            :checked="allSelected"
            :indeterminate="selected.length > 0 && !allSelected"
            @update:checked="selectAll"
          >
            选择全部
          </NCheckbox>
          <NButton
            v-if="fullIds.length"
            text
            @click="selectFullEpisodes"
          >
            <template #icon><Check :size="15" /></template>
            只选整期
          </NButton>
          <span class="ml-auto text-meta text-muted">已选择 {{ selected.length }} 条</span>
        </div>

        <ProgrammeContentList
          v-model="selected"
          :contents="contents"
          :full-ids="fullIds"
          @preview="openPreview"
          @download="addDownloads"
        />
      </template>
    </template>
  </div>

  <ProgrammePreviewDialog
    v-model="preview"
    :quality="settings.quality"
  />
</template>

<style scoped>
@reference '../../../styles/global.css';

@layer components {
  .detail-heading {
    @apply mb-[34px] flex items-center gap-6;

    @variant max-[1020px] {
      @apply gap-[18px];
    }

    @variant max-[760px] {
      @apply flex-wrap gap-4;
    }

    @variant max-[440px] {
      @apply gap-3;
    }
  }

  .detail-cover {
    @apply aspect-[16/10] w-[184px] shrink-0 overflow-hidden rounded-[9px] border border-line;

    @variant max-[1020px] {
      @apply w-[130px];
    }

    @variant max-[760px] {
      @apply w-[110px];
    }

    @variant max-[440px] {
      @apply w-[88px];
    }
  }

  .content-toolbar {
    @apply flex items-center justify-between gap-5 px-6 py-[18px];

    @variant max-[760px] {
      @apply flex-wrap gap-3 p-5;
    }
  }

  .content-toolbar > :deep(.n-button) {
    @variant max-[760px] {
      @apply ml-auto!;
    }
  }

  .selection-toolbar {
    @apply flex flex-wrap items-center gap-[25px] bg-subtle px-6 py-[11px];

    @variant max-[760px] {
      @apply gap-[15px] px-5 py-3;
    }
  }
}
</style>

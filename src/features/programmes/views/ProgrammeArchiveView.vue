<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'

import { RouterLink } from 'vue-router'
import { NButton, NCheckbox, useMessage } from 'naive-ui'
import { ArrowLeft, CalendarDays, Star } from '@lucide/vue'

import { errorMessage } from '@/shared/utils/errors'
import { useProgrammeDownloads } from '@/features/programmes/composables/useProgrammeDownloads'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'
import { useProgrammeCatalogueStore } from '@/features/programmes/stores/useProgrammeCatalogueStore'
import { useProgrammeArchive } from '@/features/programmes/composables/useProgrammeArchive'
import { useContentSelection } from '@/features/programmes/composables/useContentSelection'
import CoverImage from '@/shared/components/CoverImage.vue'
import StatePanel from '@/shared/components/StatePanel.vue'
import ProgrammeDatePicker from '@/features/programmes/components/ProgrammeDatePicker.vue'
import ProgrammeContentList from '@/features/programmes/components/ProgrammeContentList.vue'
import ProgrammePreviewDialog from '@/features/programmes/components/ProgrammePreviewDialog.vue'
import ProgrammeDownloadButton from '@/features/programmes/components/ProgrammeDownloadButton.vue'

import type { ContentRef } from '@shared/contracts/programmes'
import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'
import type { ContentSortOrder } from '@/features/programmes/model/content-presentation'

const props = defineProps<{ id: string }>()

const catalogue = useProgrammeCatalogueStore()
const settings = useSettingsStore()
const message = useMessage()

const programmeId = computed(() => props.id)
const programme = computed(() => catalogue.programmes.find((item) => item.id === programmeId.value))
const programmeName = computed(() => programme.value?.name ?? '')
const isFavourite = computed(
  () => !!programme.value && settings.favourites.includes(programme.value.id),
)

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
const contentSortOrder = ref<ContentSortOrder>('asc')
const { preparingIds, prepareDownloads } = useProgrammeDownloads()

const selectedDateId = computed(
  () => dates.value.find((date) => date.date === selectedDate.value)?.id || '',
)
const previewReference = computed<ContentRef | null>(() =>
  preview.value
    ? {
        programmeId: props.id,
        dateId: selectedDateId.value,
        contentId: preview.value.id,
      }
    : null,
)
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

const selectionButtonTheme = {
  heightMedium: '36px',
  fontSizeMedium: '14px',
  fontWeight: '500',
  paddingMedium: '0 10px',
}

function openPreview(content: ProgrammeContent) {
  preview.value = content
}

async function downloadContents(items: ProgrammeContent[], quality: Quality) {
  try {
    const result = await prepareDownloads(items, selectedDateId.value, quality, props.id)

    if (!result || result.kind === 'cancelled') {
      return
    }

    const { failures, usedFallback } = result
    const accepted = result.kind === 'browser' ? result.handedOff : result.taskIds.length
    const fallback = usedFallback
      ? `，缺少${quality === 'smooth' ? '流畅' : '标准'}版本的内容使用${quality === 'smooth' ? '标准' : '流畅'}画质`
      : ''
    const success =
      result.kind === 'browser'
        ? `${accepted} 个视频已交给浏览器${fallback}`
        : `${accepted} 个视频已加入下载队列${fallback}`

    if (failures.length) {
      const error = `${failures.length} 个视频下载失败。${failures[0]?.message}`

      if (accepted) {
        message.warning(`${success}；${error}`, { duration: 8000 })
      } else {
        message.error(error, { duration: 8000 })
      }
    } else {
      message.success(success)
    }
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
  <div class="programme-view">
    <RouterLink
      to="/"
      class="back-link"
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
      <div class="detail-copy">
        <h1 class="detail-title">
          {{ programmeName || '电视节目' }}
        </h1>
        <span class="detail-meta">
          <CalendarDays :size="15" />
          <span class="detail-date-summary">{{ dateSummary }}</span>
          <span
            v-if="dates.length"
            class="detail-date-summary"
          >
            · {{ dates.at(-1)?.date }} 起
          </span>
        </span>
      </div>
      <NButton
        v-if="programme"
        class="detail-favourite"
        :type="isFavourite ? 'primary' : 'default'"
        secondary
        @click="settings.toggleFavourite(programme.id)"
      >
        <template #icon>
          <Star
            :size="16"
            :fill="isFavourite ? 'currentColor' : 'none'"
          />
        </template>
        {{ isFavourite ? '已收藏' : '收藏栏目' }}
      </NButton>
    </section>

    <div class="content-panel">
      <section class="date-panel">
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
      </section>

      <template v-if="!loadingDates && !dateError && dates.length">
        <div class="content-toolbar">
          <div class="content-count">
            <h2 class="content-date">{{ selectedDate }}</h2>
            <span class="content-kind">节目内容</span>
            <span
              v-if="!loadingContents && !contentError"
              class="content-total"
            >
              {{ contents.length }} 条
            </span>
          </div>
          <div
            v-if="!loadingContents && !contentError && contents.length"
            class="content-actions"
          >
            <div class="selection-toolbar">
              <span class="selection-summary">已选 {{ selected.length }} 条</span>
              <NButton
                v-if="fullIds.length"
                quaternary
                :theme-overrides="selectionButtonTheme"
                @click="selectFullEpisodes"
              >
                只选整期
              </NButton>
              <NCheckbox
                :theme-overrides="{ fontSizeMedium: '14px' }"
                :checked="allSelected"
                :indeterminate="selected.length > 0 && !allSelected"
                @update:checked="selectAll"
              >
                选择全部
              </NCheckbox>
            </div>
            <ProgrammeDownloadButton
              :contents="selectedContents"
              :disabled="preparingIds.length > 0"
              label="批量下载"
              :primary="selected.length > 0"
              @download="downloadContents(selectedContents, $event)"
            />
          </div>
        </div>

        <StatePanel
          v-if="loadingContents"
          class="content-state"
          loading
        />
        <StatePanel
          v-else-if="contentError"
          class="content-state"
          title="节目内容加载失败"
          :error="contentError"
          @retry="loadContents"
        />
        <StatePanel
          v-else-if="!contents.length"
          class="content-state"
          title="这一天还没有节目内容"
          description="试试其他播出日期。"
        />

        <template v-else>
          <ProgrammeContentList
            v-model="selected"
            v-model:sort-order="contentSortOrder"
            :contents="contents"
            :full-ids="fullIds"
            :preparing-ids="preparingIds"
            @preview="openPreview"
            @download="downloadContents"
          />
        </template>
      </template>
    </div>

    <ProgrammePreviewDialog
      v-model="preview"
      :quality="settings.quality"
      :reference="previewReference"
    />
  </div>
</template>

<style scoped>
.back-link {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  margin-bottom: 20px;
  font-size: 14px;
  color: var(--muted);
}
.detail-heading {
  display: flex;
  align-items: center;
  gap: 24px;
  margin-bottom: 28px;
}
.detail-cover {
  view-transition-name: programme-cover;
  aspect-ratio: 16 / 10;
  width: 184px;
  flex-shrink: 0;
  overflow: hidden;
  border-radius: 9px;
  border: 1px solid var(--line);
}
.detail-copy {
  min-width: 0;
  flex: 1;
}
.detail-title {
  font-size: 28px;
  overflow-wrap: anywhere;
}
.detail-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 7px;
  margin-top: 13px;
  font-size: 14px;
  color: var(--muted);
}
.detail-date-summary {
  white-space: nowrap;
}
.date-panel,
.content-state {
  border-radius: 12px;
  border: 1px solid var(--line);
  background: var(--panel);
}
.content-toolbar {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto auto;
  align-items: center;
  gap: 20px;
  padding: 24px 0 16px;
}
.content-count {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 4px 10px;
  min-width: 0;
}
.content-actions {
  display: contents;
}
.content-date {
  font-size: 18px;
  line-height: 1.5;
  font-weight: 600;
}
.content-kind {
  font-size: 14px;
  color: var(--muted);
}
.content-total {
  font-size: 14px;
  color: var(--muted);
}
.selection-toolbar {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 8px;
  white-space: nowrap;
}
.selection-summary {
  margin-right: 8px;
  font-size: 13px;
  color: var(--muted);
}
@media (width < 1200px) {
  .content-toolbar {
    grid-template-columns: minmax(0, 1fr) auto;
    row-gap: 8px;
  }
  .selection-toolbar {
    grid-column: 1 / -1;
    grid-row: 2;
  }
}
@media (hover: hover) {
  .back-link:hover {
    color: var(--accent);
  }
}
@media (width < 1020px) {
  .detail-heading {
    gap: 18px;
  }
  .detail-cover {
    width: 130px;
  }
  .detail-favourite {
    align-self: flex-start;
  }
}
@media (width < 760px) {
  .back-link {
    min-height: 44px;
    margin-bottom: 8px;
  }
  .detail-heading {
    display: grid;
    grid-template-columns: 88px minmax(0, 1fr);
    gap: 10px 12px;
    margin-bottom: 20px;
  }
  .detail-cover {
    align-self: start;
    width: 88px;
  }
  .detail-title {
    margin-top: 0;
    font-size: 22px;
  }
  .detail-meta {
    gap: 4px;
    margin-top: 6px;
    font-size: 13px;
    line-height: 1.5;
  }
  .detail-date-summary {
    white-space: normal;
  }
  .detail-favourite {
    grid-column: 2;
    justify-self: start;
    min-height: 44px;
  }
  .content-toolbar {
    gap: 4px 12px;
    padding: 20px 0 8px;
  }
  .content-count {
    display: block;
  }
  .content-date {
    font-size: 16px;
  }
  .content-kind {
    display: none;
  }
  .content-total {
    display: block;
    margin-top: 4px;
    font-size: 13px;
  }
  .selection-toolbar {
    gap: 4px;
  }
  .selection-toolbar :deep(.n-checkbox) {
    min-height: 44px;
    align-items: center;
  }
  .selection-toolbar :deep(.n-checkbox__label) {
    font-size: 14px;
  }
  .selection-toolbar :deep(.n-button) {
    min-height: 44px;
    font-size: 14px;
  }
  .selection-summary {
    font-size: 12px;
    white-space: nowrap;
  }
}
</style>

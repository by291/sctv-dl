<script setup lang="ts">
import { computed, onDeactivated, onMounted, ref, shallowRef } from 'vue'

import { RouterLink } from 'vue-router'
import { NButton, NCheckbox, useMessage } from 'naive-ui'
import { ArrowLeft, CalendarDays, Star } from '@lucide/vue'

import { useArchiveBrowseState } from '@/features/programmes/composables/useArchiveBrowseState'
import { useArchiveBrowseRestoration } from '@/features/programmes/composables/useArchiveBrowseRestoration'
import { usePlatform } from '@/shared/platform/usePlatform'
import ProgrammeUpdateNotice from '@/features/programmes/components/ProgrammeUpdateNotice.vue'
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

import type { PreviewInput } from '@/features/programmes/model/playback-state'
import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'

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

const platform = usePlatform()
const preview = ref<ProgrammeContent | null>(null)
const previewInput = shallowRef<PreviewInput | null>(null)
const browse = useArchiveBrowseState(programmeId, platform.programmeCache)
const interactionHold = computed(
  () => !!preview.value || selected.value.length > 0 || preparingIds.value.length > 0,
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
  pendingUpdate,
  cached,
  fetchedAt,
  refreshError,
  cacheWarning,
  acceptUpdate,
  selectionNotice,
  datesLoaded,
  contentsLoaded,
} = useProgrammeArchive(programmeId, platform.programmes, platform.programmeCache, {
  interactionHold,
  restoration: { ready: () => browse.ready, saved: browse.saved },
})
const { selected, allSelected, fullIds, selectAll, selectFullEpisodes } = useContentSelection(
  contents,
  programmeName,
  selectedDate,
)

const { preparingIds, prepareDownloads } = useProgrammeDownloads()

const selectedDateId = computed(
  () => dates.value.find((date) => date.date === selectedDate.value)?.id || '',
)
const { contentSortOrder, preserveScrollAfter } = useArchiveBrowseRestoration({
  programmeId,
  browse,
  datesLoaded,
  contentsLoaded,
  selectedDateId,
  selectedDate,
})

const previewReference = computed(() => previewInput.value?.metadata.content ?? null)
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
  if (!selectedDate.value || !selectedDateId.value) {
    return
  }

  // Pin IDs and presentation before archive requests can replace their source state.
  const pinned = { ...content }
  previewInput.value = {
    kind: 'online',
    content: pinned,
    metadata: {
      content: { programmeId: props.id, dateId: selectedDateId.value, contentId: content.id },
      programmeName: programmeName.value,
      broadcastDate: selectedDate.value,
      title: content.title,
      cover: content.cover,
    },
  }
  preview.value = pinned
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

function refreshArchive() {
  void loadDates()
  if (selectedDateId.value) {
    void loadContents()
  }
}

async function applyUpdate() {
  if (interactionHold.value) {
    return
  }

  await preserveScrollAfter(acceptUpdate)
}

onDeactivated(() => {
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

    <ProgrammeUpdateNotice
      :pending="pendingUpdate"
      :held="interactionHold"
      :cached="cached"
      :fetched-at="fetchedAt"
      :refresh-error="refreshError"
      :cache-warning="cacheWarning || browse.warning.value"
      @accept="applyUpdate"
      @retry="refreshArchive"
    />
    <p
      v-if="selectionNotice"
      class="archive-selection-notice"
      role="status"
    >
      {{ selectionNotice }}
    </p>
    <div class="content-panel">
      <section class="date-panel">
        <ProgrammeDatePicker
          v-model="selectedDate"
          :dates="dates"
          :loading="loadingDates"
          @refresh="refreshArchive"
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
      :input="previewInput"
    />
  </div>
</template>

<style scoped>
.archive-selection-notice {
  margin-bottom: 12px;
  color: var(--muted);
  font-size: 13px;
}
.back-link {
  display: inline-flex;
  min-height: 32px;
  align-items: center;
  gap: 7px;
  margin-bottom: 16px;
  font-size: 13px;
  color: var(--muted);
  transition: color var(--motion-fast) var(--motion-ease);
}
.detail-heading {
  display: grid;
  grid-template-columns: clamp(272px, 26cqw, 330px) minmax(0, 1fr) auto;
  align-items: center;
  gap: 28px;
  margin-bottom: 30px;
}
.detail-cover {
  view-transition-name: programme-cover;
  aspect-ratio: 16 / 9;
  width: 100%;
  overflow: hidden;
  border-radius: var(--radius);
  border: 1px solid var(--line);
  background: var(--subtle);
}
.detail-copy {
  min-width: 0;
}
.detail-favourite {
  min-height: 40px;
}
.detail-title {
  font-size: clamp(28px, 2.8cqw, 37px);
  line-height: 1.2;
  font-weight: 800;
  letter-spacing: -0.4px;
  overflow-wrap: anywhere;
}
.detail-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  margin-top: 14px;
  font-size: 13px;
  color: var(--muted);
}
.detail-date-summary {
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
.date-panel,
.content-state {
  border-radius: var(--radius);
  border: 1px solid var(--line);
  background: var(--panel);
}
.content-toolbar {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto auto;
  align-items: center;
  gap: 20px;
  padding: 26px 0 14px;
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
  font-size: 20px;
  line-height: 1.5;
  font-weight: 700;
  letter-spacing: -0.2px;
  font-variant-numeric: tabular-nums;
}
.content-kind {
  font-size: 13px;
  color: var(--muted);
}
.content-total {
  font-size: 13px;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
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
  font-size: 12px;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
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
@container workspace (width < 940px) {
  .detail-heading {
    grid-template-columns: min(340px, 50%) minmax(0, 1fr);
    gap: 20px;
  }
  .detail-cover {
    grid-row: 1 / span 2;
  }
  .detail-copy {
    align-self: end;
  }
  .detail-favourite {
    grid-column: 2;
    align-self: start;
    justify-self: start;
  }
}
@container workspace (width < 520px) {
  .detail-heading {
    grid-template-columns: minmax(0, 1fr);
    gap: 16px;
    margin-bottom: 24px;
  }
  .detail-cover {
    grid-row: auto;
    max-width: 420px;
  }
  .detail-copy {
    align-self: auto;
  }
  .detail-title {
    font-size: 25px;
  }
  .detail-favourite {
    grid-column: 1;
  }
}
@media (width < 760px) {
  .back-link {
    min-height: 44px;
    margin-bottom: 8px;
  }
  .detail-meta {
    gap: 4px;
    margin-top: 8px;
    font-size: 12px;
    line-height: 1.5;
  }
  .detail-date-summary {
    white-space: normal;
  }
  .content-toolbar {
    gap: 4px 12px;
    padding: 20px 0 8px;
  }
  .content-count {
    display: block;
  }
  .content-date {
    font-size: 17px;
  }
  .content-kind {
    display: none;
  }
  .content-total {
    display: block;
    margin-top: 4px;
    font-size: 12px;
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

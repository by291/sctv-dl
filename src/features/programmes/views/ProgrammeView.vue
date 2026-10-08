<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'

import { RouterLink } from 'vue-router'
import { NButton, NCheckbox, useMessage } from 'naive-ui'
import { ArrowLeft, CalendarDays, Star, Check } from '@lucide/vue'

import { errorMessage } from '../../../shared/errors'
import { makeDownloadFile } from '../../downloads/model'
import { handOffDownload } from '../../downloads/browser-download'
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
const downloadingIds = ref<string[]>([])
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

async function downloadContents(items: ProgrammeContent[], quality: Quality) {
  if (!items.length || downloadingIds.value.length) {
    return
  }

  downloadingIds.value = items.map((item) => item.id)

  try {
    const files = items.map((item) => makeDownloadFile(item, selectedDate.value || '', quality))
    const failures: string[] = []
    let handedOff = 0
    let usedFallback = false

    // Await only preparation; the browser owns each file's transfer and completion.
    for (const file of files) {
      try {
        await handOffDownload(file)
        handedOff += 1
        usedFallback ||= file.quality !== quality
      } catch (cause) {
        failures.push(`${file.title}：${errorMessage(cause)}`)
      }
    }

    const fallback = usedFallback
      ? `，缺少${quality === 'smooth' ? '流畅' : '标准'}版本的内容使用${quality === 'smooth' ? '标准' : '流畅'}画质`
      : ''
    const success = `${handedOff} 个视频已交给浏览器${fallback}`

    if (failures.length) {
      const error = `${failures.length} 个视频下载失败。${failures[0]}`

      if (handedOff) {
        message.warning(`${success}；${error}`, { duration: 8000 })
      } else {
        message.error(error, { duration: 8000 })
      }
    } else {
      message.success(success)
    }
  } catch (cause) {
    message.error(errorMessage(cause))
  } finally {
    downloadingIds.value = []
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

  <div class="content-panel">
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
        <div class="content-count">
          <h2 class="content-date">{{ selectedDate }}</h2>
          <span class="content-kind">节目内容</span>
          <span
            v-if="!loadingContents && !contentError"
            class="content-total"
          >
            {{ contents.length }} 条内容
          </span>
        </div>
        <ProgrammeDownloadButton
          v-if="!loadingContents && !contentError && contents.length"
          :contents="selectedContents"
          :disabled="downloadingIds.length > 0"
          label="批量下载"
          primary
          @download="downloadContents(selectedContents, $event)"
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
          <span class="selection-summary">已选择 {{ selected.length }} 条</span>
        </div>

        <ProgrammeContentList
          v-model="selected"
          :contents="contents"
          :full-ids="fullIds"
          :downloading-ids="downloadingIds"
          @preview="openPreview"
          @download="downloadContents"
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
.back-link {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  margin-bottom: 25px;
  font-size: 14px;
  color: var(--muted);
}
.detail-heading {
  display: flex;
  align-items: center;
  gap: 24px;
  margin-bottom: 34px;
}
.detail-cover {
  aspect-ratio: 16 / 10;
  width: 184px;
  flex-shrink: 0;
  overflow: hidden;
  border-radius: 9px;
  border: 1px solid var(--line);
}
.detail-copy {
  flex: 1;
}
.detail-title {
  margin-top: 6px;
  font-size: 28px;
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
.content-panel {
  border-radius: 12px;
  border: 1px solid var(--line);
  background: var(--panel);
}
.content-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  padding: 18px 24px;
}
.content-count {
  display: flex;
  align-items: baseline;
  gap: 13px;
}
.content-date {
  font-size: 18px;
  line-height: 1.5;
  font-weight: 600;
}
.content-kind {
  font-size: 16px;
  color: var(--text);
}
.content-total {
  font-size: 14px;
  color: var(--muted);
}
.selection-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 25px;
  background: var(--subtle);
  padding: 11px 24px;
}
.selection-summary {
  margin-left: auto;
  font-size: 14px;
  color: var(--muted);
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
  .content-count {
    flex-wrap: wrap;
    gap: 7px;
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
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 12px;
    padding: 16px;
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
    flex-wrap: nowrap;
    gap: 8px;
    padding: 8px 16px;
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

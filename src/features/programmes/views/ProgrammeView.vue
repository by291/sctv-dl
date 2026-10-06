<script setup lang="ts">
import '../styles.css'
import { computed, onMounted, ref, watch } from 'vue'

import { RouterLink, useRoute, useRouter } from 'vue-router'
import { NButton, NCheckbox, NRadioGroup, NRadioButton, useMessage } from 'naive-ui'
import { ArrowLeft, CalendarDays, Download, Star, Check } from '@lucide/vue'

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

import type { ProgrammeContent } from '../types'

const route = useRoute()
const router = useRouter()
const catalogue = useProgrammeStore()
const downloads = useDownloadStore()
const settings = useSettingsStore()
const message = useMessage()

const programmeId = computed(() => String(route.params.id))
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
const { selected, quality, allSelected, fullIds, selectAll, selectFullEpisodes, videoNote } =
  useContentSelection(contents, programmeName, selectedDate, settings.quality)
const preview = ref<ProgrammeContent | null>(null)

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

function addSelected(openQueue = false) {
  try {
    const tasks = contents.value
      .filter((item) => selected.value.includes(item.id))
      .map((item) =>
        makeDownloadTask(
          item,
          programmeName.value || '电视节目',
          selectedDate.value || '',
          quality.value,
        ),
      )
    const count = downloads.add(tasks)
    message.success(count ? `已加入 ${count} 个下载任务` : '所选内容已在下载列表中')

    if (tasks.some((task) => task.quality !== quality.value)) {
      message.info('部分内容没有所选版本，已使用可用画质，详见任务列表')
    }

    if (openQueue) {
      void router.push('/downloads')
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
      <div class="eyebrow">PROGRAMME ARCHIVE</div>
      <h1>{{ programmeName || '电视节目' }}</h1>
      <p>按播出日期，找到你想留下的整期与片段。</p>
      <span class="detail-meta">
        <CalendarDays :size="15" />
        {{ dateSummary }}
        <span v-if="dates.length">· {{ dates.at(-1)?.date }} 起</span>
      </span>
    </div>
    <NButton
      v-if="programme"
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
          <h2>
            {{ selectedDate }}
            <span>节目内容</span>
          </h2>
          <span v-if="!loadingContents">{{ contents.length }} 条内容</span>
        </div>
        <div class="quality-control">
          <span>画质</span>
          <NRadioGroup
            v-model:value="quality"
            name="quality"
            size="small"
            aria-label="下载画质"
          >
            <NRadioButton value="standard">标准</NRadioButton>
            <NRadioButton value="smooth">流畅</NRadioButton>
          </NRadioGroup>
        </div>
      </div>

      <StatePanel
        v-if="loadingContents"
        loading
      />
      <StatePanel
        v-else-if="contentError"
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
            size="small"
            @click="selectFullEpisodes"
          >
            <template #icon><Check :size="15" /></template>
            只选整期
          </NButton>
          <span>已选择 {{ selected.length }} 条</span>
        </div>

        <ProgrammeContentList
          v-model="selected"
          :contents="contents"
          :full-ids="fullIds"
          :quality="quality"
          :video-note="videoNote"
          @preview="openPreview"
        />

        <div class="download-action">
          <div>
            <strong>
              {{ selected.length ? `已选 ${selected.length} 条节目内容` : '选择想要收藏的内容' }}
            </strong>
            <p>加入列表后，可在下载任务中开始保存。</p>
          </div>
          <div class="action-buttons">
            <NButton
              :disabled="!selected.length"
              @click="addSelected()"
            >
              加入任务
            </NButton>
            <NButton
              type="primary"
              :disabled="!selected.length"
              @click="addSelected(true)"
            >
              <template #icon><Download :size="17" /></template>
              加入并查看任务
            </NButton>
          </div>
        </div>
      </template>
    </template>
  </div>

  <ProgrammePreviewDialog
    v-model="preview"
    :quality="quality"
  />
</template>

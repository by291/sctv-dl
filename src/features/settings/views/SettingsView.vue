<script setup lang="ts">
import { computed, onMounted } from 'vue'

import { NButton, NRadioGroup, NRadioButton } from 'naive-ui'
import { SlidersHorizontal, Palette, Radio, RefreshCw } from '@lucide/vue'

import { useSettingsStore } from '../store'
import { useProgrammeStore } from '../../programmes/store'

const themeOptions = [
  { label: '跟随系统', value: 'system' },
  { label: '浅色', value: 'light' },
  { label: '深色', value: 'dark' },
]

const settings = useSettingsStore()
const programmes = useProgrammeStore()
const lastUpdated = computed(
  () =>
    programmes.updatedAt?.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' }) ||
    '尚未检查',
)
onMounted(() => {
  void programmes.load()
})
</script>

<template>
  <div class="settings-view">
    <section class="page-heading">
      <div>
        <h1>设置</h1>
      </div>
    </section>

    <div
      v-if="!settings.persisted"
      class="notice warning"
    >
      浏览器未允许本地存储，本次设置可能无法在刷新后保留。
    </div>

    <div class="settings-sections">
      <section class="settings-card">
        <div class="settings-title">
          <SlidersHorizontal :size="20" />
          <h2 class="settings-heading">播放与下载</h2>
        </div>
        <div class="setting-row">
          <div class="setting-description">
            <h3 class="setting-label">默认预览画质</h3>
            <p class="setting-help">播放时优先使用该画质，不可用时自动使用另一版本。</p>
          </div>
          <NRadioGroup
            v-model:value="settings.quality"
            name="default-quality"
            aria-label="默认预览画质"
            class="setting-options"
          >
            <NRadioButton value="standard">标准</NRadioButton>
            <NRadioButton value="smooth">流畅</NRadioButton>
          </NRadioGroup>
        </div>
        <div class="setting-row">
          <div class="setting-description">
            <h3 class="setting-label">保存位置</h3>
            <p class="setting-help">
              由浏览器的下载设置决定。若要每次选择目录，请在浏览器中开启“下载前询问保存位置”。
            </p>
          </div>
          <span class="pill">浏览器管理</span>
        </div>
      </section>
      <section class="settings-card">
        <div class="settings-title">
          <Palette :size="20" />
          <h2 class="settings-heading">外观</h2>
        </div>
        <div class="setting-row">
          <div class="setting-description">
            <h3 class="setting-label">界面主题</h3>
          </div>
          <NRadioGroup
            v-model:value="settings.theme"
            name="theme"
            aria-label="界面主题"
            class="setting-options"
          >
            <NRadioButton
              v-for="option in themeOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </NRadioButton>
          </NRadioGroup>
        </div>
      </section>
      <section class="settings-card">
        <div class="settings-title">
          <Radio :size="20" />
          <h2 class="settings-heading">节目服务</h2>
        </div>
        <div class="setting-row">
          <div class="setting-description">
            <h3 class="setting-label">
              <span
                class="status-dot connection-status"
                :class="{ offline: programmes.error }"
              />
              {{
                programmes.error
                  ? '连接暂时不可用'
                  : programmes.updatedAt
                    ? '已连接四川观察节目服务'
                    : '正在检查连接'
              }}
            </h3>
            <p class="setting-help">
              {{
                programmes.error ||
                `已读取 ${programmes.programmes.length} 个栏目 · 最近检查 ${lastUpdated}`
              }}
            </p>
          </div>
          <NButton
            secondary
            :loading="programmes.loading"
            @click="programmes.load(true)"
          >
            <template #icon><RefreshCw :size="16" /></template>
            检查连接
          </NButton>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.settings-sections {
  display: grid;
  gap: 22px;
}
.settings-card {
  border-radius: 11px;
  border: 1px solid var(--line);
  background: var(--panel);
  padding: 24px;
}
.settings-title {
  display: flex;
  align-items: center;
  gap: 10px;
  border-bottom: 1px solid var(--line);
  padding-bottom: 19px;
  color: var(--muted);
}
.settings-heading {
  font-size: 18px;
  line-height: inherit;
  font-weight: 600;
  color: var(--text);
}
.setting-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 25px;
  padding-top: 22px;
}
.setting-description {
  max-width: 450px;
}
.setting-label {
  font-size: 16px;
  font-weight: 500;
}
.setting-help {
  margin-top: 7px;
  font-size: 14px;
  line-height: 1.9;
  color: var(--muted);
}
.setting-options {
  flex-shrink: 0;
}
.connection-status {
  margin-right: 7px;
}
@media (width < 760px) {
  .settings-sections {
    gap: 16px;
  }
  .settings-card {
    padding: 16px;
  }
  .settings-title {
    padding-bottom: 14px;
  }
  .setting-row {
    flex-direction: column;
    align-items: stretch;
    gap: 12px;
    padding-top: 18px;
  }
  .setting-description {
    max-width: none;
  }
  .setting-options {
    display: flex;
  }
  .setting-options :deep(.n-radio-button) {
    flex: 1;
    text-align: center;
  }
  .setting-row > .pill,
  .setting-row > :deep(.n-button) {
    align-self: flex-start;
  }
}
</style>

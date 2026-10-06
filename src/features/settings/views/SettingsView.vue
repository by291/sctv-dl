<script setup lang="ts">
import '../styles.css'
import { computed, onMounted } from 'vue'

import { NButton, NSelect, NRadioGroup, NRadioButton } from 'naive-ui'
import { SlidersHorizontal, Palette, Radio, RefreshCw, Tv, ExternalLink } from '@lucide/vue'

import { useSettingsStore } from '../store'
import { useProgrammeStore } from '../../programmes/store'

const themeOptions = [
  { label: '浅色', value: 'light' },
  { label: '深色', value: 'dark' },
  { label: '跟随系统', value: 'system' },
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
  <section class="page-heading">
    <div>
      <div class="eyebrow">PREFERENCES</div>
      <h1>
        按照你的习惯
        <span class="title-dot">.</span>
      </h1>
      <p>一点简单的设置，让收藏节目更顺手。</p>
    </div>
  </section>

  <div
    v-if="!settings.persisted"
    class="notice warning"
  >
    浏览器未允许本地存储，本次设置可能无法在刷新后保留。
  </div>

  <div class="settings-layout">
    <div class="settings-sections">
      <section class="settings-card">
        <div class="settings-title">
          <SlidersHorizontal :size="20" />
          <h2>下载偏好</h2>
        </div>
        <div class="setting-row">
          <div>
            <h3>默认画质</h3>
            <p>流畅画质文件通常更小；没有流畅版本时会使用标准画质。</p>
          </div>
          <NRadioGroup
            v-model:value="settings.quality"
            name="default-quality"
            aria-label="默认下载画质"
          >
            <NRadioButton value="standard">标准</NRadioButton>
            <NRadioButton value="smooth">流畅</NRadioButton>
          </NRadioGroup>
        </div>
        <div class="setting-row">
          <div>
            <h3>保存位置</h3>
            <p>由浏览器的下载设置决定。若要每次选择目录，请在浏览器中开启“下载前询问保存位置”。</p>
          </div>
          <span class="pill">浏览器管理</span>
        </div>
      </section>
      <section class="settings-card">
        <div class="settings-title">
          <Palette :size="20" />
          <h2>外观</h2>
        </div>
        <div class="setting-row">
          <div>
            <h3>界面主题</h3>
            <p>选择适合你当前环境的颜色。</p>
          </div>
          <NSelect
            v-model:value="settings.theme"
            :options="themeOptions"
            aria-label="界面主题"
          />
        </div>
      </section>
      <section class="settings-card">
        <div class="settings-title">
          <Radio :size="20" />
          <h2>节目服务</h2>
        </div>
        <div class="setting-row">
          <div>
            <h3>
              <span :class="['status-dot', { offline: programmes.error }]" />
              {{
                programmes.error
                  ? '连接暂时不可用'
                  : programmes.updatedAt
                    ? '已连接四川观察节目服务'
                    : '正在检查连接'
              }}
            </h3>
            <p>
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
    <aside class="about-card">
      <span class="brand-icon"><Tv :size="25" /></span>
      <h2>sctv-dl</h2>
      <span class="pill">Web · 0.1.0</span>
      <p>
        一个简单的四川电视节目收藏工具。
        <br />
        <br />
        找到一段喜欢的内容，选好日期，再把它留在身边。
      </p>
      <div>
        <ExternalLink :size="16" />
        <span>
          下载由浏览器完成
          <br />
          设置与任务保存在本机
        </span>
      </div>
    </aside>
  </div>
</template>

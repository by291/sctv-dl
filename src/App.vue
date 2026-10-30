<script setup lang="ts">
import { computed } from 'vue'
import {
  NConfigProvider,
  NGlobalStyle,
  NMessageProvider,
  darkTheme,
  zhCN,
  dateZhCN,
} from 'naive-ui'

import { darkThemeOverrides, lightThemeOverrides } from '@/theme/naive-ui-theme'
import { useAppTheme } from '@/theme/useAppTheme'
import AppLayout from '@/layouts/AppLayout.vue'

const { isDark } = useAppTheme()
const activeThemeOverrides = computed(() =>
  isDark.value ? darkThemeOverrides : lightThemeOverrides,
)
</script>

<template>
  <NConfigProvider
    :theme="isDark ? darkTheme : null"
    :theme-overrides="activeThemeOverrides"
    :locale="zhCN"
    :date-locale="dateZhCN"
  >
    <NGlobalStyle />
    <NMessageProvider>
      <AppLayout />
    </NMessageProvider>
  </NConfigProvider>
</template>

<script setup lang="ts">
import { NConfigProvider, NMessageProvider, darkTheme, zhCN, dateZhCN } from 'naive-ui'

import { themeOverrides } from './app/theme'
import { useAppTheme } from './app/useAppTheme'
import AppLayout from './layouts/AppLayout.vue'

const { isDark } = useAppTheme()
</script>

<template>
  <NConfigProvider
    :theme="isDark ? darkTheme : null"
    :theme-overrides="themeOverrides"
    :locale="zhCN"
    :date-locale="dateZhCN"
  >
    <NMessageProvider>
      <AppLayout />
    </NMessageProvider>
  </NConfigProvider>
</template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { Copy, Minus, Square, X } from '@lucide/vue'

import type { WindowControlsPort } from '@/shared/platform/ports'

const props = defineProps<{ controls: WindowControlsPort }>()
const maximized = ref(false)

let stopResize: (() => void) | undefined
let isMounted = false
let readRevision = 0

async function syncMaximized(): Promise<void> {
  const revision = ++readRevision
  try {
    const isMaximized = await props.controls.isMaximized()
    // Resize and button queries can complete out of order.
    if (isMounted && revision === readRevision) {
      maximized.value = isMaximized
    }
  } catch (cause) {
    // Window chrome has no in-app error surface; the native controls remain usable.
    console.error('Failed to read maximized state', cause)
  }
}

function run(action: Promise<void>): void {
  void action.catch((cause) => {
    console.error('Window control failed', cause)
  })
}

function minimize(): void {
  run(props.controls.minimize())
}

async function toggleAndReadMaximized(): Promise<void> {
  await props.controls.toggleMaximize()
  if (isMounted) {
    await syncMaximized()
  }
}

function toggleMaximize(): void {
  run(toggleAndReadMaximized())
}

function close(): void {
  run(props.controls.close())
}

async function observeMaximized(): Promise<void> {
  try {
    const unlisten = await props.controls.onResized(() => {
      if (isMounted) {
        void syncMaximized()
      }
    })
    // Registration can finish after component teardown.
    if (!isMounted) {
      unlisten()

      return
    }

    stopResize = unlisten
  } catch (cause) {
    console.error('Failed to observe window size', cause)
  }

  // Subscribe before taking the initial snapshot so no resize falls between them.
  if (isMounted) {
    await syncMaximized()
  }
}

onMounted(() => {
  isMounted = true
  void observeMaximized()
})

onBeforeUnmount(() => {
  isMounted = false
  stopResize?.()
})
</script>

<template>
  <div
    class="window-title-bar"
    data-tauri-drag-region
  >
    <div
      class="window-controls"
      role="group"
      aria-label="窗口控制"
    >
      <button
        type="button"
        class="window-control"
        aria-label="最小化"
        title="最小化"
        @click="minimize"
      >
        <Minus :size="14" />
      </button>
      <button
        type="button"
        class="window-control"
        :aria-label="maximized ? '还原' : '最大化'"
        :title="maximized ? '还原' : '最大化'"
        @click="toggleMaximize"
      >
        <Copy
          v-if="maximized"
          :size="13"
        />
        <Square
          v-else
          :size="12"
        />
      </button>
      <button
        type="button"
        class="window-control close"
        aria-label="关闭"
        title="关闭"
        @click="close"
      >
        <X :size="14" />
      </button>
    </div>
  </div>
</template>

<style scoped>
.window-title-bar {
  --focus: var(--accent);

  position: relative;
  display: flex;
  height: 32px;
  flex-shrink: 0;
  justify-content: flex-end;
  background: var(--bg);
  user-select: none;
}
.window-title-bar::before {
  content: '';
  position: absolute;
  inset: 0 auto 0 0;
  width: var(--sidebar-width, 240px);
  background: var(--rail);
}
.window-controls {
  position: relative;
  z-index: 1;
  display: flex;
  height: 100%;
}
.window-control {
  display: grid;
  width: 46px;
  height: 100%;
  place-items: center;
  border: 0;
  background: transparent;
  color: var(--muted);
  transition:
    background-color var(--motion-fast) var(--motion-ease),
    color var(--motion-fast) var(--motion-ease);
}
.window-control:hover {
  background: var(--subtle);
  color: var(--text);
}
.window-control.close:hover {
  background: var(--accent-fill);
  color: #fff;
}
.window-control:focus-visible {
  outline: 2px solid var(--focus) !important;
  outline-offset: -3px !important;
}
@media (width < 760px) {
  .window-title-bar {
    --focus: var(--rail-text);
  }
  .window-control {
    color: var(--rail-muted);
  }
  .window-control:hover {
    background: var(--rail-hover);
    color: var(--rail-text);
  }
  .window-control.close:hover {
    background: var(--accent-fill);
    color: #fff;
  }
}
</style>

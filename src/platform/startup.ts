export async function startWithRecovery(
  root: HTMLElement,
  start: () => Promise<void>,
): Promise<void> {
  try {
    await start()
  } catch {
    const notice = document.createElement('p')
    notice.setAttribute('role', 'alert')
    notice.textContent = '应用启动失败，请重试。'
    const retry = document.createElement('button')
    retry.type = 'button'
    retry.textContent = '重新启动'
    retry.addEventListener(
      'click',
      () => {
        retry.disabled = true
        void startWithRecovery(root, start)
      },
      { once: true },
    )
    root.replaceChildren(notice, retry)
  }
}

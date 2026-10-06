export class LatestRequest {
  private version = 0
  private controller?: AbortController

  begin() {
    this.cancel()
    const version = this.version
    const controller = (this.controller = new AbortController())

    return {
      signal: controller.signal,
      isCurrent: () => version === this.version && !controller.signal.aborted,
    }
  }

  cancel() {
    this.version++
    this.controller?.abort()
  }
}

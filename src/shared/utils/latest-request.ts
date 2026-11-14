export class LatestRequest {
  private version = 0
  private controller?: AbortController

  // Open a request whose results can be committed only while it remains current.
  begin(): { signal: AbortSignal; isCurrent(): boolean } {
    this.cancel()
    const version = this.version
    const controller = new AbortController()
    this.controller = controller

    // Cancellation may arrive too late; the version also prevents obsolete state commits.
    return {
      signal: controller.signal,
      isCurrent: () => version === this.version && !controller.signal.aborted,
    }
  }

  // Invalidate the current request even if its transport cannot cancel promptly.
  cancel(): void {
    this.version++
    this.controller?.abort()
  }
}

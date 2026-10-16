export class LatestRequest {
  private version = 0
  private controller?: AbortController

  begin(): { signal: AbortSignal; isCurrent(): boolean } {
    this.cancel()
    const version = this.version
    const controller = (this.controller = new AbortController())

    // Cancellation may arrive too late; the version also prevents obsolete state commits.
    return {
      signal: controller.signal,
      isCurrent: () => version === this.version && !controller.signal.aborted,
    }
  }

  cancel(): void {
    this.version++
    this.controller?.abort()
  }
}

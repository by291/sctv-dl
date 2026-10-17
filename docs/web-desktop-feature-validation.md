# Web and Desktop Feature Validation

## Scope and Host

Validation on 2026-10-18 covers viewing history/resume, durable native downloads, and metadata caching/browse restoration. Android and Flutter work is outside this report. Windows runtime, minimum macOS, signed distribution, and cross-client migration are not covered.

## Browser Evidence

An isolated Chrome origin on port 5189 exercised the actual Web application and programme service. Desktop and 390-pixel views were inspected in light and dark themes. Checks included the history empty state, populated history, settings maintenance controls, keyboard cancellation of confirmation, archive loading, cached entry, and retained content after a failed refresh.

A real 70-second clip was played briefly, closed at 15 seconds, and reopened from history at 15 seconds while paused. No full episode was downloaded. An independent request through the media proxy used Range `bytes=0-1023`: it returned 206, `video/mp4`, exactly 1,024 bytes, and `Content-Range: bytes 0-1023/26618835`.

Reload retained the saved descending sort and restored the prior archive position. Browser verification found a missing immediate save after selecting a new date; after correction, selecting October 16 and reloading retained October 16. Stopping the disposable Vite server and refreshing the dates displayed a refresh failure while retaining all 14 visible programme rows. Clearing metadata cache left viewing history available.

A temporary browser fixture rendered the actual download components with eight synthetic task states. Desktop and 390-pixel layouts were checked in light and dark themes. Batch pause reported one processed, six skipped, and one failed task; the failed filename and cause remained visible. Local playback failure showed an explicit retry action. Keyboard Escape closed the playback dialog, and keyboard Enter on Cancel dismissed the file deletion confirmation. A narrow-screen overflow in that confirmation was corrected using the library's width property and visually rechecked. This fixture validates presentation and interaction only, not native transfer or OS file operations. The fixture and disposable preview processes were removed after the run; theme and viewport overrides were restored.

## Follow-up UI and Navigation Checks

Follow-up browser checks covered history cover playback, the redesigned download rows, direct batch buttons in the list header, and single-line playback titles. Desktop and narrow layouts retained the same task-list position before and after selection. Each navigation tab retains its page and scroll position, and shared cover transitions remain available after tab switches.

Regression tests cover negative WebKit bounce offsets, unchanged live scroll geometry, normalized native browse-state command arguments, and recovery from a browse-state save warning. The native WebView bounce gesture itself was not re-tested interactively.

## Native Interactive Evidence and Limits

An isolated macOS release bundle with identifier `dev.sctvdl.acceptance20261018` launched successfully and loaded 40 programmes through the native service. Its window then stopped providing reliable rendered updates and screenshot access to the automation tool. Native menu Quit completed successfully. The installed-app download, restart recovery, local playback, directory picker, and external file actions therefore remain unverified interactively. Automated Rust coverage below does not close this runtime acceptance gap.

## Automated Boundaries

Colocated tests cover history session/sequence ordering, deletion invalidation, completion/resume policy, IndexedDB reconnect and quota recovery, cross-tab ownership, native post-replacement sync failures, explicit playback retry, quality-switch resets, and inactive-player autoplay suppression.

Cache tests cover valid empty snapshots, effective-field equality, generation fencing, clear during reads/writes, capacity limits, accepted/pending refresh state, selection holds, saved date/sort/scroll, and cancellation of delayed scroll restoration by user interaction.

Native download tests use disposable files and local HTTP fixtures. They cover pause/resume representation validation and byte equality, recovery identity checks, owned-artifact preservation, completed/missing records, local HEAD/Range streaming, per-attempt actions, deduplication, monotonic events during disk writes, and finalization/stop races. Exit tests cover rejected quit, durable pause/reopen, failed checkpoints, repeated force-exit confirmation, and retained partial files.

## Verification Results

| Check                                      | Result                                                                 |
| ------------------------------------------ | ---------------------------------------------------------------------- |
| `pnpm check`                               | Passed: 570 tests in 79 files, TypeScript checks, ESLint, and Prettier |
| `pnpm build`                               | Passed                                                                 |
| `pnpm desktop:check`                       | Passed: rustfmt, Clippy with warnings denied, and 127 Rust tests       |
| `pnpm desktop:build --bundles app`         | Passed on macOS                                                        |
| Isolated acceptance bundle                 | Built and launched; interactive limits recorded above                  |
| Documentation links and `git diff --check` | Passed                                                                 |

Validation did not include pushing, deployment, Developer ID signing, notarization, Windows execution, or release certification. The local macOS bundle uses the build tool's ad-hoc signature.

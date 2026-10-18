# Web and Desktop Feature Validation

## Scope and Host

Validation on 2026-10-18 covers viewing history/resume, durable native downloads, and metadata caching/browse restoration. The initial browser/macOS run and subsequent Windows run are recorded separately below. Android, Flutter, minimum OS versions, signed distribution, and cross-client migration are outside this report.

## Browser Evidence

An isolated Chrome origin on port 5189 exercised the actual Web application and programme service. Desktop and 390-pixel views were inspected in light and dark themes. Checks included the history empty state, populated history, settings maintenance controls, keyboard cancellation of confirmation, archive loading, cached entry, and retained content after a failed refresh.

A real 70-second clip was played briefly, closed at 15 seconds, and reopened from history at 15 seconds while paused. No full episode was downloaded. An independent request through the media proxy used Range `bytes=0-1023`: it returned 206, `video/mp4`, exactly 1,024 bytes, and `Content-Range: bytes 0-1023/26618835`.

Reload retained the saved descending sort and restored the prior archive position. Browser verification found a missing immediate save after selecting a new date; after correction, selecting October 16 and reloading retained October 16. Stopping the disposable Vite server and refreshing the dates displayed a refresh failure while retaining all 14 visible programme rows. Clearing metadata cache left viewing history available.

A temporary browser fixture rendered the actual download components with eight synthetic task states. Desktop and 390-pixel layouts were checked in light and dark themes. Batch pause reported one processed, six skipped, and one failed task; the failed filename and cause remained visible. Local playback failure showed an explicit retry action. Keyboard Escape closed the playback dialog, and keyboard Enter on Cancel dismissed the file deletion confirmation. A narrow-screen overflow in that confirmation was corrected using the library's width property and visually rechecked. This fixture validates presentation and interaction only, not native transfer or OS file operations. The fixture and disposable preview processes were removed after the run; theme and viewport overrides were restored.

## Follow-up UI and Navigation Checks

Follow-up browser checks covered history cover playback, the redesigned download rows, direct batch buttons in the list header, and single-line playback titles. Desktop and narrow layouts retained the same task-list position before and after selection. Each navigation tab retains its page and scroll position, and shared cover transitions remain available after tab switches.

Regression tests cover negative WebKit bounce offsets, unchanged live scroll geometry, normalized native browse-state command arguments, and recovery from a browse-state save warning. The native WebView bounce gesture itself was not re-tested interactively.

## macOS Interactive Evidence and Limits

An isolated macOS release bundle with identifier `dev.sctvdl.acceptance20261018` launched successfully and loaded 40 programmes through the native service. Its window then stopped providing reliable rendered updates and screenshot access to the automation tool. Native menu Quit completed successfully. The installed-app download, restart recovery, local playback, directory picker, and external file actions therefore remain unverified interactively. Automated Rust coverage below does not close this runtime acceptance gap.

## Automated Boundaries

Colocated tests cover history session/sequence ordering, deletion invalidation, completion/resume policy, IndexedDB reconnect and quota recovery, cross-tab ownership, native post-replacement sync failures, explicit playback retry, quality-switch resets, and inactive-player autoplay suppression.

Cache tests cover valid empty snapshots, effective-field equality, generation fencing, clear during reads/writes, capacity limits, accepted/pending refresh state, selection holds, saved date/sort/scroll, and cancellation of delayed scroll restoration by user interaction.

Native download tests use disposable files and local HTTP fixtures. They cover pause/resume representation validation and byte equality, recovery identity checks, owned-artifact preservation, completed/missing records, local HEAD/Range streaming, per-attempt actions, deduplication, monotonic events during disk writes, and finalization/stop races. Exit tests cover rejected quit, durable pause/reopen, failed checkpoints, repeated force-exit confirmation, and retained partial files.

## Browser/macOS Verification Results

| Check                                      | Result                                                                 |
| ------------------------------------------ | ---------------------------------------------------------------------- |
| `pnpm check`                               | Passed: 570 tests in 79 files, TypeScript checks, ESLint, and Prettier |
| `pnpm build`                               | Passed                                                                 |
| `pnpm desktop:check`                       | Passed: rustfmt, Clippy with warnings denied, and 127 Rust tests       |
| `pnpm desktop:build --bundles app`         | Passed on macOS                                                        |
| Isolated acceptance bundle                 | Built and launched; interactive limits recorded above                  |
| Documentation links and `git diff --check` | Passed                                                                 |

Validation did not include pushing, deployment, Developer ID signing, notarization, Windows execution, or release certification. The local macOS bundle uses the build tool's ad-hoc signature.

## Windows Follow-up

### Host and Build

The Windows follow-up used x64 build 26300.9711 (DisplayVersion 26H2), WebView2 155.0.4283.62, Node 26.10.0, pnpm 12.9.1, and Rust/Cargo 1.99.0. The production executable was launched directly from the build output with bundled frontend assets and no project Node service. This is evidence for this host, not the proposed Windows 10/11 minimum support matrix.

The first Rust test executable failed before entering its test harness with `0xc0000139` (`STATUS_ENTRYPOINT_NOT_FOUND`). Its native dialog dependency imports Common Controls v6 APIs, but the executable had no embedded manifest. Embedding Tauri's default manifest into a disposable copy allowed the harness to start. The MSVC build now embeds the Common Controls v6 dependency through the linker for both application and test executables, with Tauri's duplicate application manifest disabled on that target. The rebuilt production manifest retained `asInvoker` and `uiAccess=false`.

| Check                            | Windows result                                                                         |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| `pnpm install --frozen-lockfile` | Passed                                                                                 |
| `pnpm check`                     | Passed: 570 tests in 79 files, TypeScript checks, ESLint, and Prettier                 |
| `pnpm desktop:check`             | Passed: rustfmt, Clippy with warnings denied, Rust unit/integration tests and doctests |
| `pnpm desktop:build`             | Passed: frontend production build, native release executable, and x64 NSIS installer   |

An initial shared-check run overlapped native compilation and timed out in the Vite-startup test's 10-second setup hook. Its isolated rerun and the subsequent full shared check both passed. The sandbox's Corepack registry lookup also failed with `ENOTFOUND`; host execution completed successfully with the pinned tooling.

The initial installer was `src-tauri/target/release/bundle/nsis/SCTV DL_0.1.0_x64-setup.exe` (4.01 MiB), SHA-256 `BA486F90299AAFBFEF0FE4BEFBAA4C11D8F6CC3F9E781DBBB6A372E4587A522B`. That unsigned installer was exercised as recorded below and was subsequently replaced by the customized build.

### Interactive Runtime Evidence

- The native programme service loaded 40 programmes. The selected news programme loaded 3,396 dates and 14 content rows for October 17. Light and dark themes were inspected at the default desktop window size.
- A real 4:02 clip played with changing frames. Seeking reached 00:59, and switching from standard to smooth quality retained that position. The preview's close button worked. This was a short playback sample, not a full-length playback endurance check.
- Cancelling the native folder picker preserved the unset location. Selecting a disposable directory whose name contained Chinese characters and a space persisted successfully. Smooth quality, dark theme, the directory, completed tasks, and viewing history survived a graceful exit and restart.
- The smooth clip downloaded as a 27,262,842-byte MP4. Playback from its completed task worked and retained progress; a subsequent restart restored history at 01:19 while paused.
- A full episode downloaded as a 551,769,005-byte MP4. Rejecting the active-download exit confirmation returned to the application and allowed the transfer to finish. Downloading that episode again reserved a suffixed filename without replacing the completed file.
- Accepting exit during the second full-episode transfer durably paused it at 367,525,888 bytes. Restart displayed the task at 66%, with zero running transfers and an explicit continue action. Continuing completed the file. Both full-episode files had identical SHA-256 `7E20FF9609FE3E78668105F9FDF27F0564BE8E34CE16E52770D01979DBAF49E3`; no partial file or journal remained after completion.

The initial test started without application data. After that run, the application was closed and the task-created preferences, history, cache, WebView profile, and downloaded fixtures were removed. Build outputs were retained.

### Installer, Narrow Window, and Keyboard Follow-up

The NSIS wizard completed a per-user installation into its default location. The installed application launched and loaded the programme catalogue. Its executable, uninstall entry, desktop shortcut, and Start Menu shortcut were observed. Because the installer was launched from the packaged Codex environment, the running executable's physical path was under Codex's `LocalCache/Local/SCTV DL`, although the wizard and uninstall registration displayed the ordinary user-local path.

Dragging the outer window border reached the configured 380-by-540 minimum client size (approximately 384-by-591 including decorations). Checks covered the programme library and search, programme details and date navigation, content actions, the player dialog, populated viewing history, the empty download page, and settings. Light and dark views were inspected. Navigation and controls remained accessible; the date strip and download filters retained their intended horizontal scrolling. This does not add populated-download or live error-state coverage at that size.

Keyboard checks confirmed search text entry, Tab movement from search to sorting and programme links, Enter opening the sort menu and entering a programme, and Escape dismissing the sort menu. Automated Escape did not dismiss the player dialog. The installed focus-trap dependency checks `KeyboardEvent.code`, which suggested a possible difference in injected key events, but the event payload was not instrumented. The user then pressed a physical Escape key and confirmed that the player closed; the next captured application state also showed the history page without the dialog. This establishes the physical Escape result without attributing a proven application defect to the automation failure. Automated player hotkeys and a full keyboard-only navigation audit remain outside the passing results.

The automation tool blocked launching the uninstaller with `product policy blocks this app`, so the user ran it manually and reported completion. Post-uninstall inspection found the program directory removed and no application or associated WebView2 processes running. However, the Start Menu shortcut and uninstall registration remained. The user also reported manually deleting a shortcut, so the absent desktop shortcut is not evidence of automatic removal. Application preferences, history, cache, and the WebView profile remained as well.

Uninstallation therefore did not pass a complete cleanup check in this initial run. Installation inside the packaged Codex environment and manual uninstallation outside it may have affected path/registry visibility; this is a hypothesis, not an established cause. After recording the results, only the known test-created profile, remaining shortcut, and stale uninstall registration were removed manually. The installer build output was retained. A later ordinary-user-context repeat is recorded below.

### Customized Installer Follow-up

The replacement x64 NSIS package is 4,196,953 bytes, SHA-256 `52A094D3BC81890BC84F3D9706A4B965AC33641D34C6E01EC9E86E00DC64C778`. Its Chinese welcome, installation directory, completion, uninstall confirmation, and uninstall completion pages were inspected. The welcome contains the approved title, programme description, and next-step instruction. Completion offers immediate launch and desktop-shortcut creation. The uninstall data checkbox is unchecked by default, and its complete Chinese label fits the dialog.

The user launched this installer from File Explorer. The executable was installed at the ordinary user-local path. Both desktop and Start Menu shortcuts were observed pointing to that executable. After default uninstallation, the application directory and both shortcuts were absent. The retained `desktop.json` had the same SHA-256 before and after uninstall, and the local cache/WebView directory remained. The previous shortcut-removal failure did not reproduce in this run.

The user then reinstalled the same package and opened its uninstaller again. Selecting application-data removal completed successfully: the application directory, desktop and Start Menu shortcuts, and both Roaming/Local `dev.sctvdl.desktop` directories were absent afterward. The data cleared in this run consisted of the verification profile and cache. The uninstaller was closed after inspection. Video preservation was covered by the native disposable fixture rather than by downloading another video during this second uninstall.

Code inspection identified a separate stock-template issue: installation-location and language metadata were only removed when the user also selected application-data removal. The new cleanup hook separates installation metadata from that choice, preserves upgrade state and registrations for another location, and retains unrelated values. A native NSIS regression fixture verifies those actual registry operations, including a trailing directory separator. It also verifies private-data deletion while retaining external/nested video files, unfinished downloads, and directory junction targets. The initial failing fixtures passed after the production cleanup implementation was added. `pnpm check`, `pnpm desktop:check`, `pnpm desktop:build`, and final NSIS repackaging passed. The cleanup fixture is now wired into Windows CI; remote CI was not run locally.

The automation process's registry view still contained the earlier language-1033 metadata and did not expose the new uninstall entry even before uninstallation. Full real-install registry cleanup therefore cannot be claimed from that view; the registry result above is established by the isolated native fixture. No additional broad registry deletion was added to compensate for this environment discrepancy.

### Installer Visual Refinement

The refined package at the same build-output path is 4,225,400 bytes, SHA-256 `FEDF072545CEB08F3C331488185ADAB08E0DE2ED0E85000A5FA8F99F8B52F37D`. `pnpm check` passed all 570 tests plus type/lint/format checks. A fresh `pnpm desktop:build` completed frontend and native compilation and generated the NSIS bundle. The cleanup regression fixture also passed again.

The subsequent visual pass replaced the base-resolution artwork with 656-by-1,256 sidebar and 600-by-228 header bitmaps sourced from the 512-pixel application icon. Sidebar brand and subtitle lettering now use native controls. Header title and description share the same left edge in both wizards. Both small and large window icons are explicitly loaded from the application ICO, and extraction of the actual installed uninstaller's file icon also showed the red television mark.

That refinement placed the optional data-removal checkbox in a separate bottom region with a section label and a video-preservation explanation. It remained unchecked initially. Interactive checks covered welcome, directory, completion, uninstall confirmation, and uninstall completion pages on the current display configuration (Windows records 144 DPI / 150%). Tab reached the checkbox after the path field, and Space checked and unchecked it. Other display scales and moving the wizard between monitors were not exercised.

A first refinement candidate left an empty installation directory because temporary icon extraction changed the process working directory. The final hook extracts directly to `$PLUGINSDIR` without changing `$OUTDIR` or the working directory. After rebuilding, the user installed that final package from Explorer and opened its uninstaller. Default uninstallation completed, and inspection after closing the wizard confirmed that the installation directory and both shortcuts were absent. The package hash remained the value recorded above. The installer does not need a generated template or a new runtime dependency for these changes.

### Explorer File Icons and Compact Uninstall Option

Explorer continued to show generic NSIS file icons at the original setup and uninstall paths even though the executable resources contained the application icon. Byte-identical copies at fresh paths immediately displayed the red television icon in Explorer. An item-change notification did not clear the stale images; a Shell icon-cache refresh did. Both original paths then displayed the red television icon without renaming the files or restarting Explorer. This was a local cache issue; the bundled icon resources did not need another change.

The bottom uninstall option has been reduced to the existing checkbox alone, without the section heading or helper label. The introductory uninstall text still explains video preservation. A fresh `pnpm desktop:build` generated a 4,222,581-byte package, SHA-256 `97157933E355F1513959DA81CE733C50CF8FABA08F61BDC7E1CFDA974D3A0847`. The native cleanup regression fixture passed again. After the user installed this package and opened its uninstaller, the single-row bottom layout was visually confirmed. The checkbox was initially unchecked; Tab reached it after the installation path, and Space toggled it in both directions. It was restored to unchecked and the wizard was cancelled, leaving the updated application installed.

### Distinct Uninstaller Icon

The uninstaller now has a grey television with a red minus badge, derived from the existing television vector. Its ICO contains 16, 24, 32, 48, 64, and 256-pixel images. Both the executable resource and the explicit small/large window-icon loader use this asset; the application and setup keep their red television icon. The generated 32- and 128-pixel images were visually checked. A fresh `pnpm desktop:build` produced a 4,246,754-byte NSIS package, SHA-256 `48A7E26875AC6227FEF36A309F264C38DF89F702A0EF15F13243C0964CFFBA0D`. After installation, the actual uninstaller window displayed the grey television and minus badge. Explorer initially retained its previously cached red icon; after a Shell cache refresh, the original installed file displayed the new grey icon beside the red application icon. The wizard was cancelled without uninstalling. The first `pnpm check` run hit a five-second timeout in the existing browser-history scroll test (569 tests passed); an unchanged full rerun passed all 570 tests, type checking, lint, and formatting.

### Remaining Windows Acceptance

Signing, remote CI, minimum supported OS versions, external open/reveal actions, and live native failure states were not exercised. The ordinary-context installer repeat covers program files and shortcuts; its registry-observation limitation is recorded above. Narrow-window and keyboard results are limited to the specific interactions recorded in the follow-up.

A single post-playback snapshot totalled approximately 569 MiB working set and 350 MiB private memory across the native process and its WebView2 processes. It is not a baseline comparison or evidence of long-playback memory stability. Fullscreen and picture-in-picture also remain outside this Windows run.

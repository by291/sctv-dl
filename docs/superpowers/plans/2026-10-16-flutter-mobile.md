# Flutter Mobile Client Implementation Record

The original approved plan was committed **before implementation** in `7bff698` (`docs: plan complete Flutter mobile client`). Its execution checklist is retired here; Git retains the original plan. The [approved specification](../specs/2026-10-16-flutter-mobile-design.md) owns product contracts, the [Flutter README](../../../flutter/README.md) owns current commands and source ownership, and [Flutter Validation](../../flutter-validation.md) owns exact evidence and pending acceptance.

## Delivered Work

| Original task            | Result                                                                                                                                                                                        |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scaffold and contracts   | Independent Android/iOS hosts, identifiers, locked dependencies, immutable models and shared-contract fixture policies.                                                                       |
| Native capabilities      | Player, native holding queue, MediaStore/Files actions, backup rules, permissions and scoped native channels.                                                                                 |
| Data and persistence     | Bounded guest API, validated string IDs/dates/media, keyed snapshots, Drift user/runtime separation, preferences, favourites and 500-entry history.                                           |
| Application and browsing | Retained navigation, themes, catalogue/search/exploration, favourites/history, date archive, accepted updates, batch selection and settings.                                                  |
| Durable downloads        | Reservations, per-attempt fencing, actual progress, partial batches, pause/resume/cancel/retry, recoverable publication, local playback and file actions.                                     |
| Playback and history     | Paused online/local initialization, current quality/fallback, seek/speed, source rollback, fullscreen, capability-dependent PiP, shared resume and delayed disposal.                          |
| Platform acceptance      | Controller/widget regressions, current Android/iOS native fixtures, live application journeys and release compilation. Physical/minimum-OS/background acceptance remains explicitly separate. |
| Maintenance and review   | Pinned CI, Pub dependency updates, root-tooling exclusions, portable wrapper, launcher assets, documentation and one fresh whole-change review with regression fixes.                         |

## Integration Decisions

- Plain immutable Dart models and explicit unknown-input parsers replaced the initial Freezed/json_serializable shortlist; Drift owns generated application source. This avoids generation machinery for small policy models.
- A licensed portable copy of `better_player_plus` 2.0.0 repairs native redirects, paused seek, awaited disposal, explicit PiP and extensionless MediaStore playback. Its provenance and changes remain with the package.
- Android publication uses an application-owned MediaStore operation because the downloader's same-name lookup cannot safely recover pending rows. Private bytes remain until the completed URI is durable, and failed cleanup is retried.
- The downloader owns scheduling; Dart has no second transfer queue. Initialization can recover from transient failures without duplicating observers or replaying unverified native identities.
- Notification navigation buffers a cold tap until the router exists and acknowledges only the matching Android launch intent. Route restoration retains local identity and never silently substitutes online playback.
- iOS backup exclusions cover application runtime data and the resolved downloader's own task/resume/defaults persistence, while user preferences, favourites and history remain separately eligible.

## Git and Acceptance Boundary

The first commit contains only the design, original plan and README navigation. Grouped local implementation commits on `feature/flutter-mobile` were authorized on 2026-10-17. Push, deployment, production signing and store submission remain outside that authorization. Unrelated Kotlin-client work is preserved.

Current automated and native results do not establish physical PiP/audio behavior, sustained background execution, minimum-OS support or store readiness. Continue acceptance from the dated validation record, rather than reusing this retired execution checklist.

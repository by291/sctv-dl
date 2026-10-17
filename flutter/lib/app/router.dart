import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/state_panel.dart';
import '../domain/downloads/file_gateway.dart';
import '../domain/downloads/download_task.dart';
import '../domain/playback/playback_backend.dart';
import '../domain/programmes/programme.dart';
import '../domain/programmes/programme_policy.dart';
import '../domain/programmes/programme_repository.dart';
import '../features/downloads/downloads_page.dart';
import '../features/player/player_page.dart';
import '../features/programmes/archive_controller.dart';
import '../features/programmes/archive_page.dart';
import '../features/programmes/download_quality_sheet.dart';
import '../features/programmes/library_page.dart';
import '../features/programmes/history_page.dart';
import '../features/settings/settings_page.dart';
import '../platform/playback/better_player_backend.dart';
import 'providers.dart';
import 'services.dart';

GoRouter createAppRouter(AppServices services) {
  final historyViewState = HistoryViewState();

  Future<void> download(
    BuildContext context,
    List<ProgrammeSelection> selections,
  ) async {
    final preferences = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(preferencesProvider).value;
    final result = await showDownloadQualitySheet(
      context,
      selections: selections,
      downloads: services.downloads,
      wifiOnly: preferences.wifiOnly,
      wifiPolicyLabel: Platform.isIOS ? '禁用蜂窝网络' : '仅使用 Wi-Fi',
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(downloadResultLabel(result)),
          action: SnackBarAction(
            label: '查看下载',
            onPressed: () => context.go('/downloads'),
          ),
        ),
      );
    }
  }

  Future<void> play(
    BuildContext context,
    ProgrammeSelection selection, {
    Duration? position,
  }) async {
    final Duration resume;
    try {
      resume = position ?? await _resumePosition(services, selection.ref);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法读取观看进度：$error')));
      }
      return;
    }
    if (!context.mounted) return;
    final quality = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(preferencesProvider).value.quality;
    final sources = videoSources(selection.content).toList()
      ..sort(
        (a, b) => (a.quality == quality ? 0 : 1).compareTo(
          b.quality == quality ? 0 : 1,
        ),
      );
    final ref = selection.ref;
    await context.push(
      '/play/${ref.programmeId}/${ref.dateId}/${ref.contentId}',
      extra: PlaybackInput(
        title: selection.content.title,
        sources: sources,
        preferredQuality: quality,
        selection: selection,
        initialPosition: resume,
      ),
    );
  }

  Future<void> openProgramme(BuildContext context, Programme programme) async {
    await context.push('/programme/${programme.id}', extra: programme);
    if (context.mounted) unawaited(services.library.refresh());
  }

  return GoRouter(
    restorationScopeId: 'sctv-routes',
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        restorationScopeId: 'primary-shell',
        builder: (context, state, shell) =>
            _NavigationShell(shell: shell, services: services),
        branches: [
          StatefulShellBranch(
            restorationScopeId: 'library-navigation',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => LibraryPage(
                  controller: services.library,
                  onOpenProgramme: (programme) =>
                      unawaited(openProgramme(context, programme)),
                  onShowHistory: () => context.push('/history'),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            restorationScopeId: 'download-navigation',
            routes: [
              GoRoute(
                path: '/downloads',
                builder: (context, state) => DownloadsPage(
                  repository: services.downloads,
                  wifiPolicyLabel: Platform.isIOS ? '禁用蜂窝网络' : '仅 Wi-Fi',
                  onPlayLocal: (task) {
                    context.push('/local/${Uri.encodeComponent(task.id)}');
                  },
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            restorationScopeId: 'settings-navigation',
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const _SettingsRoute(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => HistoryPage(
          history: services.history,
          viewState: historyViewState,
          onOpen: (entry) => unawaited(
            play(
              context,
              entry.selection,
              position: entry.completed ? Duration.zero : entry.position,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/programme/:id',
        builder: (context, state) => _ArchiveRoute(
          key: ValueKey('archive-${state.pathParameters['id']}'),
          services: services,
          programmeId: state.pathParameters['id']!,
          acceptedProgramme: state.extra is Programme
              ? state.extra as Programme
              : null,
          onPlay: (selection) => unawaited(play(context, selection)),
          onDownload: (items) => download(context, items),
        ),
      ),
      GoRoute(
        path: '/play/:programme/:date/:content',
        builder: (context, state) => _PlaybackRoute(
          key: ValueKey('player-${state.uri}'),
          services: services,
          target: _OnlinePlaybackTarget(
            ContentRef(
              programmeId: state.pathParameters['programme']!,
              dateId: state.pathParameters['date']!,
              contentId: state.pathParameters['content']!,
            ),
          ),
          acceptedInput: state.extra is PlaybackInput
              ? state.extra as PlaybackInput
              : null,
          onDownload: (selection) => download(context, [selection]),
        ),
      ),
      GoRoute(
        path: '/local/:taskId',
        builder: (context, state) => _PlaybackRoute(
          key: ValueKey('local-${state.pathParameters['taskId']}'),
          services: services,
          target: _LocalPlaybackTarget(state.pathParameters['taskId']!),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('页面不可用')),
      body: StatePanel(
        title: '无法打开此页面',
        message: '页面地址无效或内容已不可用。',
        onAction: () => context.go('/'),
        actionLabel: '返回节目库',
      ),
    ),
  );
}

class _SettingsRoute extends ConsumerWidget {
  const _SettingsRoute();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final preferences = ref.watch(preferencesProvider);
    return SettingsPage(
      preferences: preferences.value,
      onChanged: ref.read(preferencesProvider.notifier).save,
      onClearCache: services.clearCache,
      onClearHistory: services.history.clear,
      version: services.version,
      supportsDynamicColour: Platform.isAndroid,
      wifiPolicyDescription: Platform.isIOS
          ? '对新任务禁用蜂窝网络，其他非蜂窝连接仍可使用'
          : '仅影响之后创建的任务',
      persistenceError: preferences.error,
    );
  }
}

class _NavigationShell extends StatefulWidget {
  const _NavigationShell({required this.shell, required this.services});
  final StatefulNavigationShell shell;
  final AppServices services;
  @override
  State<_NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<_NavigationShell>
    with WidgetsBindingObserver {
  late Stream<List<DownloadTask>> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = widget.services.downloads.watchTasks();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _NavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.services.downloads, widget.services.downloads)) {
      _tasks = widget.services.downloads.watchTasks();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        widget.services.downloads.reconcile().catchError((Object error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('下载状态更新失败：$error')));
          }
        }),
      );
    }
  }

  void _select(int index) {
    widget.shell.goBranch(index);
    if (index == 0) unawaited(widget.services.library.refresh());
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<DownloadTask>>(
    stream: _tasks,
    builder: (context, snapshot) {
      final active =
          snapshot.data
              ?.where(
                (task) => switch (task.state) {
                  DownloadState.preparing ||
                  DownloadState.queued ||
                  DownloadState.running ||
                  DownloadState.waiting ||
                  DownloadState.retrying ||
                  DownloadState.finalizing => true,
                  _ => false,
                },
              )
              .length ??
          0;
      final downloadIcon = Badge(
        isLabelVisible: active > 0,
        label: Text('$active'),
        child: const Icon(Icons.download_outlined),
      );
      return PopScope(
        canPop: widget.shell.currentIndex == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.shell.currentIndex != 0) _select(0);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            return Scaffold(
              body: Row(
                children: [
                  if (wide)
                    SafeArea(
                      right: false,
                      child: NavigationRail(
                        selectedIndex: widget.shell.currentIndex,
                        onDestinationSelected: _select,
                        labelType: NavigationRailLabelType.all,
                        destinations: [
                          const NavigationRailDestination(
                            icon: Icon(Icons.live_tv_outlined),
                            selectedIcon: Icon(Icons.live_tv),
                            label: Text('节目库'),
                          ),
                          NavigationRailDestination(
                            icon: downloadIcon,
                            selectedIcon: const Icon(Icons.download),
                            label: const Text('下载'),
                          ),
                          const NavigationRailDestination(
                            icon: Icon(Icons.settings_outlined),
                            selectedIcon: Icon(Icons.settings),
                            label: Text('设置'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(child: widget.shell),
                ],
              ),
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: widget.shell.currentIndex,
                      onDestinationSelected: _select,
                      destinations: [
                        const NavigationDestination(
                          icon: Icon(Icons.live_tv_outlined),
                          selectedIcon: Icon(Icons.live_tv),
                          label: '节目库',
                        ),
                        NavigationDestination(
                          icon: downloadIcon,
                          selectedIcon: const Icon(Icons.download),
                          label: '下载',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: '设置',
                        ),
                      ],
                    ),
            );
          },
        ),
      );
    },
  );
}

Future<Programme> _resolveProgramme(
  AppServices services,
  String id, {
  required RequestScope scope,
}) async {
  scope.throwIfCancelled();
  if (!RegExp(r'^\d+$').hasMatch(id)) throw const FormatException('栏目编号无效');
  final cached = await services.programmes.cachedProgrammes();
  scope.throwIfCancelled();
  final existing = cached?.items.where((item) => item.id == id).firstOrNull;
  if (existing != null) return existing;
  final fresh = await services.programmes.refreshProgrammes(scope: scope);
  scope.throwIfCancelled();
  return fresh.items.where((item) => item.id == id).firstOrNull ??
      (throw StateError('栏目已不可用'));
}

class _ArchiveRoute extends StatefulWidget {
  const _ArchiveRoute({
    super.key,
    required this.services,
    required this.programmeId,
    required this.onPlay,
    required this.onDownload,
    this.acceptedProgramme,
  });
  final AppServices services;
  final String programmeId;
  final Programme? acceptedProgramme;
  final void Function(ProgrammeSelection) onPlay;
  final Future<void> Function(List<ProgrammeSelection>) onDownload;
  @override
  State<_ArchiveRoute> createState() => _ArchiveRouteState();
}

class _ArchiveRouteState extends State<_ArchiveRoute> {
  late Future<Programme> programme = widget.acceptedProgramme == null
      ? _resolve()
      : Future.value(widget.acceptedProgramme);
  RequestScope? _request;
  ArchiveController? controller;

  Future<Programme> _resolve() {
    _request?.cancel();
    final scope = RequestScope();
    _request = scope;
    return _resolveProgramme(widget.services, widget.programmeId, scope: scope);
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Programme>(
    future: programme,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _routeError(
          context,
          '${snapshot.error}',
          () => setState(() => programme = _resolve()),
        );
      }
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: const Text('往期回看')),
          body: const PageSkeleton(),
        );
      }
      controller ??= ArchiveController(
        repository: widget.services.programmes,
        programme: snapshot.data!,
      );
      return ArchivePage(
        controller: controller!,
        library: widget.services.library,
        onPlay: widget.onPlay,
        onDownload: widget.onDownload,
        onOpenProgramme: (item) =>
            context.replace('/programme/${item.id}', extra: item),
      );
    },
  );
}

Future<Duration> _resumePosition(
  AppServices services,
  ContentRef contentRef, {
  RequestScope? scope,
}) async {
  scope?.throwIfCancelled();
  final history = await services.history.loadHistory();
  scope?.throwIfCancelled();
  final previous = history
      .where((entry) => entry.selection.ref == contentRef)
      .firstOrNull;
  return previous == null || previous.completed
      ? Duration.zero
      : previous.position;
}

sealed class _PlaybackTarget {
  const _PlaybackTarget();
}

final class _OnlinePlaybackTarget extends _PlaybackTarget {
  const _OnlinePlaybackTarget(this.contentRef);
  final ContentRef contentRef;
}

final class _LocalPlaybackTarget extends _PlaybackTarget {
  const _LocalPlaybackTarget(this.taskId);
  final String taskId;
}

class _PlaybackRoute extends ConsumerStatefulWidget {
  const _PlaybackRoute({
    super.key,
    required this.services,
    required this.target,
    this.onDownload,
    this.acceptedInput,
  });
  final AppServices services;
  final _PlaybackTarget target;
  final PlaybackInput? acceptedInput;
  final Future<void> Function(ProgrammeSelection)? onDownload;
  @override
  ConsumerState<_PlaybackRoute> createState() => _PlaybackRouteState();
}

class _PlaybackRouteState extends ConsumerState<_PlaybackRoute> {
  late Future<PlaybackInput> input = widget.acceptedInput == null
      ? _resolve()
      : Future.value(widget.acceptedInput);
  RequestScope? _request;

  Future<PlaybackInput> _resolve() async {
    _request?.cancel();
    final scope = RequestScope();
    _request = scope;
    return switch (widget.target) {
      _OnlinePlaybackTarget(:final contentRef) => _resolveOnline(
        contentRef,
        scope,
      ),
      _LocalPlaybackTarget(:final taskId) => _resolveLocal(taskId, scope),
    };
  }

  Future<PlaybackInput> _resolveOnline(
    ContentRef contentRef,
    RequestScope scope,
  ) async {
    if (![
      contentRef.programmeId,
      contentRef.dateId,
      contentRef.contentId,
    ].every((id) => RegExp(r'^\d+$').hasMatch(id))) {
      throw const FormatException('节目编号无效');
    }
    final programme = await _resolveProgramme(
      widget.services,
      contentRef.programmeId,
      scope: scope,
    );
    scope.throwIfCancelled();
    var dates = await widget.services.programmes.cachedDates(
      contentRef.programmeId,
    );
    scope.throwIfCancelled();
    dates ??= await widget.services.programmes.refreshDates(
      contentRef.programmeId,
      scope: scope,
    );
    scope.throwIfCancelled();
    final date = dates.items
        .where((date) => date.id == contentRef.dateId)
        .firstOrNull;
    if (date == null) throw StateError('播出日期已不可用');
    var contents = await widget.services.programmes.cachedContents(
      contentRef.programmeId,
      contentRef.dateId,
    );
    scope.throwIfCancelled();
    contents ??= await widget.services.programmes.refreshContents(
      contentRef.programmeId,
      contentRef.dateId,
      scope: scope,
    );
    scope.throwIfCancelled();
    final content = contents.items
        .where((item) => item.id == contentRef.contentId)
        .firstOrNull;
    if (content == null) throw StateError('节目已不可用');
    final position = await _resumePosition(
      widget.services,
      contentRef,
      scope: scope,
    );
    scope.throwIfCancelled();
    final quality = ref.read(preferencesProvider).value.quality;
    final sources = videoSources(content).toList()
      ..sort(
        (a, b) => (a.quality == quality ? 0 : 1).compareTo(
          b.quality == quality ? 0 : 1,
        ),
      );
    return PlaybackInput(
      title: content.title,
      sources: sources,
      preferredQuality: quality,
      selection: ProgrammeSelection(
        programme: programme,
        broadcast: date,
        content: content,
      ),
      initialPosition: position,
    );
  }

  Future<PlaybackInput> _resolveLocal(String taskId, RequestScope scope) async {
    // Reconciliation checks the durable task's actual file before local restore.
    // Missing local media never resolves through the online programme endpoint.
    await widget.services.downloads.reconcile();
    scope.throwIfCancelled();
    final tasks = await widget.services.downloads.loadTasks();
    scope.throwIfCancelled();
    final task = tasks.where((task) => task.id == taskId).firstOrNull;
    final location = task?.fileLocation;
    if (task == null ||
        task.state != DownloadState.completed ||
        location == null) {
      throw StateError('下载文件已不可用，请返回下载列表重新下载');
    }
    DownloadFileLocation.parse(location);
    final position = await _resumePosition(
      widget.services,
      task.selection.ref,
      scope: scope,
    );
    scope.throwIfCancelled();
    return PlaybackInput(
      title: task.selection.content.title,
      sources: const [],
      selection: task.selection,
      localLocation: location,
      initialPosition: position,
    );
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PlaybackInput>(
    future: input,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _routeError(
          context,
          '${snapshot.error}',
          () => setState(() => input = _resolve()),
          returnLocation: widget.target is _LocalPlaybackTarget
              ? '/downloads'
              : '/',
        );
      }
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: const Text('节目播放')),
          body: const PageSkeleton(),
        );
      }
      final prepared = snapshot.data!;
      return PlayerPage(
        input: prepared,
        backend: widget.services.playback,
        surfaceBuilder: (session) => PlaybackSurface(session: session),
        history: widget.services.history,
        onDownload:
            prepared.localLocation != null ||
                prepared.selection == null ||
                widget.onDownload == null
            ? null
            : () => widget.onDownload!(prepared.selection!),
      );
    },
  );
}

Widget _routeError(
  BuildContext context,
  String message,
  VoidCallback retry, {
  String returnLocation = '/',
}) => Scaffold(
  appBar: AppBar(
    title: const Text('内容不可用'),
    leading: BackButton(onPressed: () => context.go(returnLocation)),
  ),
  body: StatePanel(title: '暂时无法打开内容', message: message, onAction: retry),
);

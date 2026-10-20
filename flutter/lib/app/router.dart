import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/archive_transition.dart';
import '../design/content_transition.dart';
import '../design/shared_cover.dart';
import '../design/state_panel.dart';
import '../domain/playback/playback_backend.dart';
import '../domain/programmes/programme.dart';
import '../features/downloads/downloads_page.dart';
import '../features/programmes/history_page.dart';
import '../features/programmes/library_page.dart';
import 'navigation_actions.dart';
import 'routes/archive_route.dart';
import 'routes/navigation_shell.dart';
import 'routes/playback_route.dart';
import 'routes/settings_route.dart';
import 'services.dart';

GoRouter createAppRouter(AppServices services) {
  final historyViewState = HistoryViewState();
  final actions = AppNavigationActions(services);

  return GoRouter(
    restorationScopeId: 'sctv-routes',
    initialLocation: '/',
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: (context, shell, children) =>
            RetainedFadeStack(
              index: shell.currentIndex,
              travelDistance: 20,
              onSettled: () =>
                  GlassContentAwareScope.maybeOf(context)?.requestSample(),
              children: [
                for (var i = 0; i < children.length; i++)
                  SharedCoverScope(
                    active: i == shell.currentIndex,
                    child: children[i],
                  ),
              ],
            ),
        restorationScopeId: 'primary-shell',
        builder: (context, state, shell) =>
            NavigationShell(shell: shell, services: services),
        branches: [
          StatefulShellBranch(
            restorationScopeId: 'library-navigation',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => LibraryPage(
                  controller: services.library,
                  onOpenProgramme: (programme) =>
                      unawaited(actions.openProgramme(context, programme)),
                  onOpenExploration: (programme) => unawaited(
                    actions.openProgramme(context, programme, featured: true),
                  ),
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
                builder: (context, state) => const SettingsRoute(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (context, state) => ArchiveTransitionPage<void>(
          key: state.pageKey,
          restorationId: state.pageKey.value,
          child: HistoryPage(
            history: services.history,
            viewState: historyViewState,
            onOpen: (entry) => unawaited(
              actions.play(
                context,
                entry.selection,
                position: entry.completed ? Duration.zero : entry.position,
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/programme/:id',
        pageBuilder: (context, state) {
          final input = state.extra;
          final accepted = switch (input) {
            (programme: final Programme programme, coverTag: String _) =>
              programme,
            Programme programme => programme,
            _ => null,
          };
          final coverTag = switch (input) {
            (programme: Programme _, coverTag: final String tag) => tag,
            _ => null,
          };

          return ArchiveTransitionPage<void>(
            key: state.pageKey,
            restorationId: state.pageKey.value,
            // Route-owned notices disappear with their source page instead of
            // migrating into retained tabs with callbacks to a disposed context.
            child: ScaffoldMessenger(
              child: ArchiveRoute(
                key: ValueKey('archive-${state.pathParameters['id']}'),
                services: services,
                programmeId: state.pathParameters['id']!,
                acceptedProgramme: accepted,
                coverTag: coverTag,
                onPlay: actions.play,
                onDownload: actions.download,
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/play/:programme/:date/:content',
        pageBuilder: (context, state) => ArchiveTransitionPage<void>(
          key: state.pageKey,
          restorationId: state.pageKey.value,
          child: ScaffoldMessenger(
            child: PlaybackRoute(
              key: ValueKey('player-${state.uri}'),
              services: services,
              target: OnlinePlaybackTarget(
                ContentRef(
                  programmeId: state.pathParameters['programme']!,
                  dateId: state.pathParameters['date']!,
                  contentId: state.pathParameters['content']!,
                ),
              ),
              acceptedInput: state.extra is PlaybackInput
                  ? state.extra as PlaybackInput
                  : null,
              onDownload: (pageContext, selection) =>
                  actions.download(pageContext, [selection]),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/local/:taskId',
        pageBuilder: (context, state) => ArchiveTransitionPage<void>(
          key: state.pageKey,
          restorationId: state.pageKey.value,
          child: PlaybackRoute(
            key: ValueKey('local-${state.pathParameters['taskId']}'),
            services: services,
            target: LocalPlaybackTarget(state.pathParameters['taskId']!),
          ),
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

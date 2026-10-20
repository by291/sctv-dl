import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../design/ios_primary_navigation.dart';
import '../../design/primary_page_scaffold.dart';
import '../../domain/downloads/download_task.dart';
import '../services.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({
    super.key,
    required this.shell,
    required this.services,
  });

  final StatefulNavigationShell shell;
  final AppServices services;

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell>
    with WidgetsBindingObserver {
  late Stream<List<DownloadTask>> _tasks;
  final _glassScope = GlobalKey<GlassContentAwareScopeState>();

  @override
  void initState() {
    super.initState();

    _tasks = widget.services.downloads.watchTasks();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant NavigationShell oldWidget) {
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
            if (usesIosGlass(context)) {
              // Includes restored and programmatic navigation. The retained
              // transition requests a final sample when its fade settles.
              _glassScope.currentState?.requestSample();
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(platformBrightness: Theme.of(context).brightness),
                child: GlassContentAwareScope(
                  key: _glassScope,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  child: Scaffold(
                    extendBody: true,
                    // One boundary survives branch changes. The floating bar stays
                    // outside the capture so its own tint cannot affect the vote.
                    body: GlassContentAwareContent(child: widget.shell),
                    bottomNavigationBar: IosPrimaryNavigation(
                      selectedIndex: widget.shell.currentIndex,
                      activeDownloads: active,
                      onSelected: _select,
                    ),
                  ),
                ),
              );
            }

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

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/cover_image.dart';
import '../../design/state_panel.dart';
import '../../domain/playback/history_repository.dart';
import '../../domain/programmes/programme.dart';
import 'library_controller.dart';
import 'components/history_card.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.controller,
    required this.history,
    required this.onOpenProgramme,
    required this.onOpenHistory,
    this.active = true,
  });
  final LibraryController controller;
  final HistoryRepository history;
  final void Function(Programme) onOpenProgramme;
  final void Function(ViewingEntry) onOpenHistory;
  final bool active;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with WidgetsBindingObserver, RestorationMixin {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _scrolls = List.generate(3, (_) => ScrollController());
  final _searchOpen = [false, false, false];
  final _restoredQueries = List.generate(3, (_) => RestorableString(''));
  final _restoredSorts = List.generate(3, (_) => RestorableBool(false));
  final _restoredSearch = List.generate(3, (_) => RestorableBool(false));
  final _restoredTab = RestorableInt(0);
  final _removingHistory = <String>{};
  late final _historyChanges = widget.history.watchHistory();

  @override
  String? get restorationId => 'programme-library';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restoredTab, 'tab');
    for (final tab in LibraryTab.values) {
      registerForRestoration(_restoredQueries[tab.index], 'query-${tab.name}');
      registerForRestoration(_restoredSorts[tab.index], 'sort-${tab.name}');
      registerForRestoration(_restoredSearch[tab.index], 'search-${tab.name}');
      controller.setQuery(tab, _restoredQueries[tab.index].value);
      if (controller.nameOrder(tab) != _restoredSorts[tab.index].value) {
        controller.toggleSort(tab);
      }
      _searchOpen[tab.index] = _restoredSearch[tab.index].value;
    }
    _tab = LibraryTab.values[_restoredTab.value.clamp(0, 2)];
    _search.text = controller.query(_tab);
  }

  var _tab = LibraryTab.all;
  var _scrollRevision = 0;
  LibraryController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onControllerChanged);
    unawaited(controller.initialize());
  }

  @override
  void didUpdateWidget(LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) unawaited(controller.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.active &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      unawaited(controller.refresh());
    }
  }

  void _onControllerChanged() {
    if (_scrollRevision == controller.scrollRevision) return;
    _scrollRevision = controller.scrollRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final scroll in _scrolls) {
        if (scroll.hasClients) scroll.jumpTo(0);
      }
    });
  }

  void _closeSearch() {
    setState(() {
      _searchOpen[_tab.index] = false;
      _search.clear();
    });
    _restoredQueries[_tab.index].value = '';
    _restoredSearch[_tab.index].value = false;
    controller.setQuery(_tab, '');
    _focus.unfocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onControllerChanged);
    _restoredTab.dispose();
    for (final value in [
      ..._restoredQueries,
      ..._restoredSorts,
      ..._restoredSearch,
    ]) {
      value.dispose();
    }
    _search.dispose();
    _focus.dispose();
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final searching = _searchOpen[_tab.index];
      return PopScope(
        canPop: !searching,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && searching) _closeSearch();
        },
        child: DefaultTabController(
          length: 3,
          initialIndex: _tab.index,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                  ? 88
                  : 64,
              title: searching
                  ? TextField(
                      controller: _search,
                      focusNode: _focus,
                      decoration: const InputDecoration(
                        hintText: '搜索栏目',
                        border: InputBorder.none,
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        _restoredQueries[_tab.index].value = value;
                        controller.setQuery(_tab, value);
                      },
                      onSubmitted: (_) => _focus.unfocus(),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (MediaQuery.textScalerOf(context).scale(1) <
                            1.5) ...[
                          Icon(
                            Icons.live_tv_rounded,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          const SizedBox(width: 10),
                        ],
                        const Flexible(
                          child: Text(
                            'sctv-dl',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
              actions: [
                if (controller.hasPendingUpdate)
                  PendingUpdateButton(onPressed: controller.acceptUpdate),
                IconButton(
                  tooltip: searching ? '关闭搜索' : '搜索栏目',
                  icon: Icon(searching ? Icons.close : Icons.search),
                  onPressed: () {
                    if (searching) {
                      _closeSearch();
                      return;
                    }
                    setState(() {
                      _searchOpen[_tab.index] = true;
                      _restoredSearch[_tab.index].value = true;
                    });
                    _focus.requestFocus();
                  },
                ),
              ],
              bottom: TabBar(
                onTap: (index) {
                  setState(() {
                    _tab = LibraryTab.values[index];
                    _restoredTab.value = index;
                    _search.text = controller.query(_tab);
                  });
                  _focus.unfocus();
                },
                tabs: const [
                  Tab(text: '全部栏目'),
                  Tab(text: '我的收藏'),
                  Tab(text: '最近观看'),
                ],
              ),
            ),
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _catalogue(LibraryTab.all),
                _catalogue(LibraryTab.favourites),
                _history(),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _catalogue(LibraryTab tab) {
    if (controller.loading && !controller.hasSnapshot) {
      return const PageSkeleton();
    }
    if (!controller.hasSnapshot && controller.error != null) {
      return StatePanel(
        title: '暂时无法加载节目库',
        message: controller.error!,
        icon: Icons.cloud_off_outlined,
        onAction: () => unawaited(controller.refresh()),
      );
    }
    final items = controller.visibleProgrammes(tab);
    if (items.isEmpty) {
      final filtering = controller.query(tab).trim().isNotEmpty;
      return StatePanel(
        title: filtering
            ? '没有找到相关栏目'
            : tab == LibraryTab.favourites
            ? '还没有收藏'
            : '暂无栏目',
        message: filtering
            ? '试试其他关键词。'
            : tab == LibraryTab.favourites
            ? '点击栏目上的收藏按钮，稍后可以从这里继续观看。'
            : '节目库暂时为空，可以稍后重试。',
        icon: filtering ? Icons.search_off : Icons.favorite_border,
        onAction: controller.error != null
            ? () => unawaited(controller.refresh())
            : null,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final columns = largeText
            ? (constraints.maxWidth / 360).floor().clamp(1, 4)
            : (constraints.maxWidth / 180).floor().clamp(2, 6);
        return CustomScrollView(
          controller: _scrolls[tab.index],
          restorationId: 'catalogue-${tab.name}',
          key: PageStorageKey('catalogue-${tab.name}'),
          slivers: [
            if (controller.error case final error?)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: CachedErrorBanner(
                    message: error,
                    onRetry: () => unawaited(controller.refresh()),
                  ),
                ),
              ),
            if (tab == LibraryTab.all &&
                controller.query(tab).isEmpty &&
                controller.featured != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: _exploration(controller.featured!),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '共 ${items.length} 个栏目',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        controller.toggleSort(tab);
                        _restoredSorts[tab.index].value = controller.nameOrder(
                          tab,
                        );
                      },
                      icon: const Icon(Icons.sort),
                      label: Text(controller.nameOrder(tab) ? '名称排序' : '默认顺序'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent:
                      (constraints.maxWidth - 32 - 12 * (columns - 1)) /
                          columns *
                          9 /
                          16 +
                      (MediaQuery.textScalerOf(context).scale(16) * 1.5 * 2 +
                          20),
                ),
                itemBuilder: (context, index) => ProgrammeCard(
                  programme: items[index],
                  favourite: controller.favourites.contains(items[index].id),
                  onOpen: () => widget.onOpenProgramme(items[index]),
                  onFavourite: () =>
                      unawaited(controller.toggleFavourite(items[index].id)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _exploration(Programme programme) {
    final colours = Theme.of(context).colorScheme;
    final typography = Theme.of(context).textTheme;
    return Card(
      color: colours.primaryContainer.withValues(alpha: .35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
            final wide = constraints.maxWidth >= 480;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '栏目探索',
                            style: typography.labelLarge?.copyWith(
                              color: colours.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            programme.name,
                            maxLines: largeText ? 4 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: typography.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (wide) ...[
                            const SizedBox(height: 8),
                            Text(
                              '发现一个栏目，回看整期节目或精彩片段。',
                              style: typography.bodyMedium?.copyWith(
                                color: colours.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!largeText) ...[
                      const SizedBox(width: 16),
                      Transform.rotate(
                        angle: -.0872665,
                        child: Container(
                          width: wide
                              ? 240
                              : (constraints.maxWidth * .46).clamp(112, 160),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colours.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: colours.shadow.withValues(alpha: .12),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CoverImage(url: programme.cover),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colours.primaryContainer,
                        foregroundColor: colours.onPrimaryContainer,
                      ),
                      onPressed: () => widget.onOpenProgramme(programme),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('查看节目'),
                    ),
                    TextButton.icon(
                      onPressed: controller.programmes.length > 1
                          ? controller.shuffleFeatured
                          : null,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('换一个'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _removeHistory(ViewingEntry entry) async {
    final key = entry.selection.ref.key;
    if (!_removingHistory.add(key)) return;
    setState(() {});
    try {
      await widget.history.remove(entry.selection.ref);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('移除失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _removingHistory.remove(key));
    }
  }

  Widget _history() => StreamBuilder<List<ViewingEntry>>(
    stream: _historyChanges,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return StatePanel(title: '观看记录读取失败', message: '${snapshot.error}');
      }
      if (!snapshot.hasData) return const PageSkeleton();
      final query = controller.query(LibraryTab.history).trim().toLowerCase();
      final items = snapshot.data!
          .where(
            (entry) =>
                '${entry.selection.programme.name} ${entry.selection.content.title}'
                    .toLowerCase()
                    .contains(query),
          )
          .toList();
      if (items.isEmpty && query.isNotEmpty) {
        return StatePanel(
          title: '没有匹配的观看记录',
          message: '试试节目名称，或清除搜索查看全部记录。',
          icon: Icons.search_off_rounded,
          actionLabel: '清除搜索',
          onAction: _closeSearch,
        );
      }
      if (items.isEmpty) {
        return const StatePanel(
          title: '暂无观看记录',
          message: '观看节目后，可以在这里继续播放。',
          icon: Icons.history,
        );
      }
      return ListView.separated(
        controller: _scrolls[2],
        restorationId: 'viewing-history',
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final entry = items[index];
          return HistoryCard(
            key: ValueKey(entry.selection.ref.key),
            entry: entry,
            onOpen: () => widget.onOpenHistory(entry),
            onRemove: _removingHistory.contains(entry.selection.ref.key)
                ? null
                : () => unawaited(_removeHistory(entry)),
          );
        },
      );
    },
  );
}

class ProgrammeCard extends StatelessWidget {
  const ProgrammeCard({
    super.key,
    required this.programme,
    required this.favourite,
    required this.onOpen,
    required this.onFavourite,
  });
  final Programme programme;
  final bool favourite;
  final VoidCallback onOpen;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                CoverImage(url: programme.cover),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    tooltip: favourite
                        ? '取消收藏 ${programme.name}'
                        : '收藏 ${programme.name}',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: colours.surface.withValues(alpha: .94),
                      foregroundColor: favourite
                          ? colours.primary
                          : colours.onSurfaceVariant,
                    ),
                    isSelected: favourite,
                    onPressed: onFavourite,
                    icon: const Icon(Icons.favorite_border, size: 22),
                    selectedIcon: const Icon(Icons.favorite, size: 22),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                programme.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

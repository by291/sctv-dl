import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/cover_image.dart';
import '../../design/state_panel.dart';
import '../../domain/playback/history_repository.dart';
import '../../domain/programmes/programme.dart';
import 'library_controller.dart';

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
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.live_tv_rounded),
                        SizedBox(width: 10),
                        Text('sctv-dl'),
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
                      (largeText ? 112 : 82),
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

  Widget _exploration(Programme programme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '栏目探索',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Text(
                programme.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => widget.onOpenProgramme(programme),
                    child: const Text('查看节目'),
                  ),
                  TextButton(
                    onPressed: controller.programmes.length > 1
                        ? controller.shuffleFeatured
                        : null,
                    child: const Text('换一个'),
                  ),
                ],
              ),
            ],
          );
          if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) return text;
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 20),
              SizedBox(
                width: constraints.maxWidth * .44,
                child: Transform.rotate(
                  angle: -.055,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CoverImage(url: programme.cover),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

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
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              onTap: () => widget.onOpenHistory(entry),
              leading: const Icon(Icons.play_circle_outline),
              title: Text(
                entry.selection.content.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${entry.selection.broadcast.date} · ${entry.completed ? '已看完' : '继续观看 ${entry.position.inMinutes}:${(entry.position.inSeconds % 60).toString().padLeft(2, '0')}'}',
              ),
              trailing: IconButton(
                tooltip: '移除观看记录',
                icon: const Icon(Icons.close),
                onPressed: () => widget.history.remove(entry.selection.ref),
              ),
            ),
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
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoverImage(url: programme.cover),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 2, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      programme.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: favourite
                        ? '取消收藏 ${programme.name}'
                        : '收藏 ${programme.name}',
                    isSelected: favourite,
                    onPressed: onFavourite,
                    icon: const Icon(Icons.favorite_border),
                    selectedIcon: const Icon(Icons.favorite),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

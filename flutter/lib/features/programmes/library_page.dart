import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';

import '../../design/content_transition.dart';
import '../../design/pending_update_notice.dart';
import '../../design/state_panel.dart';
import '../../domain/programmes/programme.dart';
import 'components/programme_card.dart';
import 'components/programme_exploration.dart';
import 'library_controller.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.controller,
    required this.onOpenProgramme,
    required this.onShowHistory,
    this.active = true,
    this.onOpenExploration,
  });

  final LibraryController controller;
  final void Function(Programme) onOpenProgramme;
  final void Function(Programme)? onOpenExploration;
  final VoidCallback onShowHistory;
  final bool active;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with WidgetsBindingObserver, RestorationMixin {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _updateNoticeAnchor = LayerLink();

  final _restoredQuery = RestorableString('');
  final _restoredSort = RestorableBool(false);
  final _restoredSearch = RestorableBool(false);
  final _restoredFilter = RestorableInt(0);

  bool get _favouritesOnly => _restoredFilter.value == 1;

  @override
  String? get restorationId => 'programme-library';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restoredFilter, 'tab');
    registerForRestoration(_restoredQuery, 'query-all');
    registerForRestoration(_restoredSort, 'sort-all');
    registerForRestoration(_restoredSearch, 'search-all');

    controller.setQuery(_restoredQuery.value);
    if (controller.nameOrder != _restoredSort.value) controller.toggleSort();
    _search.text = controller.query;
  }

  LibraryController get controller => widget.controller;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
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

  void _closeSearch() {
    setState(() {
      _restoredSearch.value = false;
      _search.clear();
    });

    _restoredQuery.value = '';
    controller.setQuery('');
    _focus.unfocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _restoredFilter.dispose();
    _restoredQuery.dispose();
    _restoredSort.dispose();
    _restoredSearch.dispose();

    _search.dispose();
    _focus.dispose();
    _scroll.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final searching = _restoredSearch.value;

      return PopScope(
        canPop: !searching,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && searching) _closeSearch();
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                ? 88
                : 64,
            title: SizedBox(
              height: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                  ? 72
                  : 48,
              child: RetainedFadeStack(
                index: searching ? 1 : 0,
                milliseconds: 120,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (MediaQuery.textScalerOf(context).scale(1) <
                            1.5) ...[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Theme.of(context).iconTheme.color,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.live_tv,
                              size: 24,
                              color: Theme.of(context).colorScheme.surface,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              text: 'sctv',
                              children: [
                                TextSpan(
                                  text: '-dl',
                                  style: TextStyle(
                                    color: Theme.of(context).iconTheme.color,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      controller: _search,
                      focusNode: _focus,
                      decoration: const InputDecoration(
                        hintText: '搜索栏目',
                        border: InputBorder.none,
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        _restoredQuery.value = value;
                        controller.setQuery(value);
                      },
                      onSubmitted: (_) => _focus.unfocus(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                tooltip: '观看历史',
                icon: const Icon(Icons.history_rounded),
                onPressed: () {
                  _focus.unfocus();
                  widget.onShowHistory();
                },
              ),
              IconButton(
                tooltip: searching ? '关闭搜索' : '搜索栏目',
                icon: Icon(searching ? Icons.close : Icons.search),
                onPressed: () {
                  if (searching) {
                    _closeSearch();
                    return;
                  }

                  setState(() {
                    _restoredSearch.value = true;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _restoredSearch.value) _focus.requestFocus();
                  });
                },
              ),
            ],
          ),
          body: PendingUpdateOverlay(
            anchor: _updateNoticeAnchor,
            visible: widget.active && controller.hasPendingUpdate,
            onUpdate: controller.acceptUpdate,
            child: _catalogue(),
          ),
        ),
      );
    },
  );

  Widget _catalogue() {
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

    final items = controller.visibleProgrammes(favouritesOnly: _favouritesOnly);

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final columns = largeText
            ? (constraints.maxWidth / 360).floor().clamp(1, 4)
            : (constraints.maxWidth / 180).floor().clamp(2, 6);
        final cardWidth =
            (constraints.maxWidth - 32 - 12 * (columns - 1)) / columns;
        final titleHeight = ProgrammeCard.titleHeight(
          context,
          controller.programmes.map((programme) => programme.name),
          cardWidth - 24,
        );

        return CustomScrollView(
          controller: _scroll,
          restorationId: 'catalogue-all',
          key: const PageStorageKey('catalogue-all'),
          slivers: [
            if (controller.favouriteError case final favouriteError?)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: CachedErrorBanner(
                    message: favouriteError,
                    onRetry: () => unawaited(controller.retryFavourites()),
                  ),
                ),
              ),
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
            if (controller.query.isEmpty && controller.featured != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: ProgrammeExploration(
                    programme: controller.featured!,
                    onOpen: () =>
                        (widget.onOpenExploration ?? widget.onOpenProgramme)(
                          controller.featured!,
                        ),
                    onShuffle: controller.programmes.length > 1
                        ? controller.shuffleFeatured
                        : null,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              sliver: SliverToBoxAdapter(
                child: CompositedTransformTarget(
                  link: _updateNoticeAnchor,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '共 ${items.length} 个栏目',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _favouritesOnly ? '显示全部栏目' : '只看收藏',
                            isSelected: _favouritesOnly,
                            icon: AnimatedSwitcher(
                              duration: motionDuration(context, 120),
                              child: Icon(
                                _favouritesOnly
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                key: ValueKey(_favouritesOnly),
                              ),
                            ),
                            style:
                                IconButton.styleFrom(
                                  foregroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  backgroundColor: _favouritesOnly
                                      ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                      : Colors.transparent,
                                ).copyWith(
                                  animationDuration: motionDuration(
                                    context,
                                    120,
                                  ),
                                ),
                            onPressed: () => setState(() {
                              _restoredFilter.value = _favouritesOnly ? 0 : 1;
                            }),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              controller.toggleSort();
                              _restoredSort.value = controller.nameOrder;
                            },
                            icon: const Icon(Icons.sort),
                            label: Text(controller.nameOrder ? '名称排序' : '默认顺序'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ContentTransition.sliver(
              background: Theme.of(context).scaffoldBackgroundColor,
              child: SliverStack(
                key: ValueKey(_favouritesOnly),
                children: [
                  // Keep the toolbar's partially scrolled position valid when
                  // filtering to a short or empty list, without eager grid layout.
                  SliverToBoxAdapter(
                    child: SizedBox(height: constraints.maxHeight),
                  ),
                  if (items.isEmpty)
                    SliverToBoxAdapter(child: _emptyCatalogue())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverGrid.builder(
                        itemCount: items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: cardWidth * 9 / 16 + titleHeight + 20,
                        ),
                        itemBuilder: (context, index) => ProgrammeCard(
                          programme: items[index],
                          favourite: controller.favourites.contains(
                            items[index].id,
                          ),
                          onOpen: () => widget.onOpenProgramme(items[index]),
                          onFavourite: () => unawaited(
                            controller.toggleFavourite(items[index].id),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyCatalogue() {
    final filtering = controller.query.trim().isNotEmpty;

    return StatePanel(
      title: filtering
          ? '没有找到相关栏目'
          : _favouritesOnly
          ? '还没有收藏'
          : '暂无栏目',
      message: filtering
          ? '试试其他关键词。'
          : _favouritesOnly
          ? '点击栏目上的收藏按钮，稍后可以从这里继续观看。'
          : '节目库暂时为空，可以稍后重试。',
      icon: filtering ? Icons.search_off : Icons.favorite_border,
      onAction: controller.error != null
          ? () => unawaited(controller.refresh())
          : null,
    );
  }
}

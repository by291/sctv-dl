import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';

import '../../design/shared_cover.dart';
import '../../design/content_transition.dart';
import '../../design/state_panel.dart';
import '../../domain/programmes/programme.dart';
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
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
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
    controller.removeListener(_onControllerChanged);
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
                    _restoredSearch.value = true;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _restoredSearch.value) _focus.requestFocus();
                  });
                },
              ),
            ],
          ),
          body: _catalogue(),
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
        return CustomScrollView(
          controller: _scroll,
          restorationId: 'catalogue-all',
          key: const PageStorageKey('catalogue-all'),
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
            if (controller.query.isEmpty && controller.featured != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: _exploration(controller.featured!),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              sliver: SliverToBoxAdapter(
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
                                animationDuration: motionDuration(context, 120),
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
                          mainAxisExtent:
                              (constraints.maxWidth - 32 - 12 * (columns - 1)) /
                                  columns *
                                  9 /
                                  16 +
                              (MediaQuery.textScalerOf(context).scale(16) *
                                      1.5 *
                                      ProgrammeCard.titleMaxLines(context) +
                                  20),
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

  Widget _exploration(Programme programme) {
    final colours = Theme.of(context).colorScheme;
    final typography = Theme.of(context).textTheme;
    final cardColour = Color.alphaBlend(
      colours.primaryContainer.withValues(alpha: .35),
      Theme.of(context).scaffoldBackgroundColor,
    );
    return Card(
      color: cardColour,
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
                ContentTransition(
                  background: cardColour,
                  milliseconds: 160,
                  child: Row(
                    key: ValueKey(programme.id),
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
                            SizedBox(
                              height:
                                  MediaQuery.textScalerOf(context)
                                      .scale(typography.titleLarge!.fontSize!) *
                                  1.3 *
                                  (largeText ? 4 : 2),
                              child: Text(
                                programme.name,
                                maxLines: largeText ? 4 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: typography.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
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
                        SizedBox(
                          width: wide
                              ? 240
                              : (constraints.maxWidth * .46).clamp(112, 160),
                          child: SharedCover(
                            tag: 'exploration-${programme.id}',
                            url: programme.cover,
                            rotation: -.0872665,
                            frameInset: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
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
                      onPressed: () =>
                          (widget.onOpenExploration ?? widget.onOpenProgramme)(
                            programme,
                          ),
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

  static int titleMaxLines(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 2 : 1;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SharedCover(
                  tag: 'catalogue-${programme.id}',
                  url: programme.cover,
                  radius: 16,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: ClipOval(
                    child: IconButton.filledTonal(
                      tooltip: favourite
                          ? '取消收藏 ${programme.name}'
                          : '收藏 ${programme.name}',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        fixedSize: const Size(32, 32),
                        padding: const EdgeInsets.all(6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                        backgroundColor: colours.surface.withValues(alpha: .94),
                        foregroundColor: favourite
                            ? colours.primary
                            : colours.onSurfaceVariant,
                      ),
                      isSelected: favourite,
                      onPressed: onFavourite,
                      icon: const Icon(Icons.favorite_border, size: 20),
                      selectedIcon: const Icon(Icons.favorite, size: 20),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                programme.name,
                maxLines: titleMaxLines(context),
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

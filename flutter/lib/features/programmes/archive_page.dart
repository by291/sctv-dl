import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/shared_cover.dart';
import '../../design/viewport_hero.dart';
import '../../design/state_panel.dart';
import '../../design/pending_update_notice.dart';
import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_policy.dart';
import 'archive_controller.dart';
import 'components/broadcast_dates.dart';
import 'components/broadcast_date_sheet.dart';
import 'library_controller.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({
    super.key,
    required this.controller,
    required this.library,
    required this.onPlay,
    required this.onDownload,
    required this.onOpenProgramme,
    this.initialDateId,
    this.coverTag,
  });
  final ArchiveController controller;
  final LibraryController library;
  final String? initialDateId;
  final String? coverTag;
  final void Function(ProgrammeSelection) onPlay;
  final Future<void> Function(List<ProgrammeSelection>) onDownload;
  final void Function(Programme) onOpenProgramme;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage>
    with WidgetsBindingObserver, RestorationMixin {
  ArchiveController get controller => widget.controller;
  final _scroll = ScrollController();
  final _updateNoticeAnchor = LayerLink();
  final _restoredDate = RestorableStringN(null);
  final _restoredSelection = RestorableString('');
  final _restoredSelectionMode = RestorableBool(false);
  final _restoredAscending = RestorableBool(true);
  bool _initialized = false;
  bool _interacted = false;
  bool _observingRestoration = false;

  @override
  String? get restorationId => 'archive-${controller.programme.id}';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restoredDate, 'broadcast');
    registerForRestoration(_restoredSelection, 'selection');
    registerForRestoration(_restoredSelectionMode, 'selection-mode');
    registerForRestoration(_restoredAscending, 'clip-ascending');
    if (_initialized) return;
    _initialized = true;
    final restoredIds = _restoredSelection.value.split(',').toSet();
    final restoredMode = _restoredSelectionMode.value;
    final dateId = _restoredDate.value ?? widget.initialDateId;
    controller.ascending = _restoredAscending.value;
    unawaited(
      controller.initialize(dateId: dateId).then((_) {
        if (!mounted) return;
        if (!_interacted &&
            restoredMode &&
            controller.selectedDate?.id == dateId) {
          controller.enterSelection();
          for (final item in controller.contents) {
            if (restoredIds.contains(item.id)) controller.toggleSelection(item);
          }
        }
        controller.addListener(_saveRestorationState);
        _observingRestoration = true;
        _saveRestorationState();
      }),
    );
  }

  void _saveRestorationState() {
    _restoredDate.value = controller.selectedDate?.id;
    _restoredSelection.value = controller.selectedIds.join(',');
    _restoredSelectionMode.value = controller.selectionMode;
    _restoredAscending.value = controller.ascending;
  }

  VoidCallback _action(VoidCallback action) => () {
    _interacted = true;
    action();
  };

  Future<void> _selectDate(BroadcastDate date) async {
    _interacted = true;
    await controller.selectDate(date);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      unawaited(controller.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_observingRestoration) controller.removeListener(_saveRestorationState);
    _restoredDate.dispose();
    _restoredSelection.dispose();
    _restoredSelectionMode.dispose();
    _restoredAscending.dispose();
    _scroll.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final picked = await showModalBottomSheet<BroadcastDate>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (context) => BroadcastDateSheet(
        dates: controller.dates,
        selectedId: controller.selectedDate?.id,
        onSelected: (date) => Navigator.pop(context, date),
      ),
    );
    if (picked != null && mounted) await _selectDate(picked);
  }

  Future<void> _download(List<ProgrammeSelection> selections) async {
    try {
      await widget.onDownload(selections);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载准备失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, widget.library]),
    builder: (context, _) => PopScope(
      canPop: !controller.selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && controller.selectionMode) controller.exitSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: controller.selectionMode
              ? IconButton(
                  tooltip: '退出批量选择',
                  icon: const Icon(Icons.close),
                  onPressed: _action(controller.exitSelection),
                )
              : null,
          title: Text(
            controller.selectionMode
                ? '已选择 ${controller.selectedIds.length} 项'
                : '往期回看',
          ),
          actions: [
            if (!controller.selectionMode &&
                controller.contents.any(
                  (item) => videoSources(item).isNotEmpty,
                ))
              IconButton(
                tooltip: '批量下载',
                onPressed: _action(controller.enterSelection),
                icon: const Icon(Icons.playlist_add_check),
              ),
          ],
        ),
        body: PendingUpdateOverlay(
          anchor: _updateNoticeAnchor,
          targetAnchor: Alignment.topCenter,
          // Compact clips start with text; keep the notice above that title.
          // Full/large-text cards start with artwork and can host it inside.
          anchorOffset: Offset(
            0,
            controller.fullEpisodes.isNotEmpty ||
                    controller.contents.isEmpty ||
                    MediaQuery.textScalerOf(context).scale(1) >= 1.5
                ? 8
                : -40,
          ),
          visible: !controller.selectionMode && controller.hasPendingUpdate,
          onUpdate: _action(controller.acceptUpdates),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final content = _archive();
              if (constraints.maxWidth < 1000) return content;
              return Row(
                children: [
                  SizedBox(width: 270, child: _libraryPane()),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: controller.selectionMode
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: controller.selectedIds.isEmpty
                        ? null
                        : () => _download(controller.selectedItems),
                    icon: const Icon(Icons.download_outlined),
                    label: Text('下载所选 ${controller.selectedIds.length} 项'),
                  ),
                ),
              )
            : null,
      ),
    ),
  );

  Widget _libraryPane() => ListView.builder(
    key: const PageStorageKey('archive-library'),
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
    itemCount: widget.library.programmes.length,
    itemBuilder: (context, index) {
      final programme = widget.library.programmes[index];
      return ListTile(
        selected: programme.id == controller.programme.id,
        title: Text(programme.name, maxLines: 2),
        trailing: widget.library.favourites.contains(programme.id)
            ? const Icon(Icons.favorite, size: 18)
            : null,
        onTap: () => widget.onOpenProgramme(programme),
      );
    },
  );

  Widget _archive() {
    final selected = controller.selectedDate;
    return CustomScrollView(
      controller: _scroll,
      restorationId: 'broadcast-content',
      slivers: [
        if (!controller.selectionMode)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _header(),
            ),
          ),
        if (controller.loadingDates)
          const SliverFillRemaining(child: PageSkeleton())
        else if (controller.dates.isEmpty && controller.error != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: StatePanel(
              title: '暂时无法加载回看',
              message: controller.error!,
              icon: Icons.cloud_off_outlined,
              onAction: () => unawaited(controller.refresh()),
            ),
          )
        else ...[
          if (controller.error case final error?)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              sliver: SliverToBoxAdapter(
                child: CachedErrorBanner(
                  message: error,
                  onRetry: () => unawaited(controller.refresh()),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: controller.selectionMode
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: _action(controller.selectAll),
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: _action(controller.selectFullEpisodes),
                          child: const Text('仅完整节目'),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: BroadcastDates(
                      dates: controller.dates,
                      selected: selected,
                      onSelected: (date) => unawaited(_selectDate(date)),
                      onMore: _chooseDate,
                    ),
                  ),
          ),
          if (selected != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.date,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${controller.fullEpisodes.length} 个完整节目 · ${controller.clips.length} 个片段',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (controller.loadingContents &&
              !controller.hasSnapshot &&
              selected != null)
            SliverToBoxAdapter(
              child: SizedBox(height: 340, child: const PageSkeleton(count: 2)),
            )
          else if (controller.contents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: CompositedTransformTarget(
                link: _updateNoticeAnchor,
                child: StatePanel(
                  title: '暂无节目内容',
                  message: selected == null ? '暂未提供播出日期。' : '这一天暂未提供节目内容。',
                  onAction: controller.error == null
                      ? null
                      : () => unawaited(controller.refresh()),
                ),
              ),
            )
          else ...[
            for (final item in controller.fullEpisodes)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: _contentCard(item, fullEpisode: true),
                ),
              ),
            if (controller.clips.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '节目片段',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: controller.ascending
                            ? '当前按时间升序，切换为降序'
                            : '当前按时间降序，切换为升序',
                        onPressed: controller.selectionMode
                            ? null
                            : _action(controller.toggleSort),
                        icon: Transform.flip(
                          flipY: controller.ascending,
                          child: const Icon(Icons.sort),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: controller.clips.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) =>
                    _contentCard(controller.clips[index], fullEpisode: false),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 24 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _header() {
    final programme = controller.programme;
    final favourite = widget.library.favourites.contains(programme.id);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          programme.name,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
          onPressed: () => widget.library.toggleFavourite(programme.id),
          icon: Icon(
            favourite ? Icons.favorite : Icons.favorite_border,
            size: 18,
          ),
          label: Text(favourite ? '已收藏' : '收藏栏目'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) return details;
        final cover = ListenableBuilder(
          listenable: _scroll,
          builder: (context, _) => SharedCover(
            // A clipped/offscreen cover must not reappear above the app bar
            // when returning from a scrolled archive.
            tag: !_scroll.hasClients || _scroll.offset <= 8
                ? widget.coverTag
                : null,
            url: programme.cover,
          ),
        );
        final compact = constraints.maxWidth < 348;
        final gap = compact ? 12.0 : 16.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: ((constraints.maxWidth - gap) * (compact ? .52 : .54))
                  .clamp(0, 256),
              child: cover,
            ),
            SizedBox(width: gap),
            Expanded(child: details),
          ],
        );
      },
    );
  }

  Widget _contentCard(ProgrammeContent item, {required bool fullEpisode}) {
    final playable = videoSources(item).isNotEmpty;
    final selected = controller.selectedIds.contains(item.id);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fullEpisode)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '完整节目',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        Text(
          item.title,
          maxLines: largeText ? 6 : 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (!fullEpisode)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              publicationLabel(
                item.publishedAt,
                controller.selectedDate?.date ?? '',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (!playable)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('暂未提供视频'),
          ),
      ],
    );
    final content = fullEpisode || largeText
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _playArtwork(
                item,
                playable,
                fullEpisode: true,
                selected: selected,
              ),
              Padding(padding: const EdgeInsets.all(16), child: details),
            ],
          )
        : Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 104,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _playArtwork(item, playable, selected: selected),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: details),
              ],
            ),
          );
    final card = Semantics(
      checked: controller.selectionMode ? selected : null,
      enabled: playable,
      label: controller.selectionMode ? item.title : null,
      child: Card(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        child: InkWell(
          onTap: !playable
              ? null
              : () {
                  if (controller.selectionMode) {
                    _action(() => controller.toggleSelection(item))();
                    return;
                  }
                  widget.onPlay(
                    ProgrammeSelection(
                      programme: controller.programme,
                      broadcast: controller.selectedDate!,
                      content: item,
                    ),
                  );
                },
          child: content,
        ),
      ),
    );
    final first =
        controller.fullEpisodes.firstOrNull ?? controller.clips.firstOrNull;
    return item.id == first?.id
        ? CompositedTransformTarget(link: _updateNoticeAnchor, child: card)
        : card;
  }

  Widget _playArtwork(
    ProgrammeContent item,
    bool playable, {
    bool fullEpisode = false,
    required bool selected,
  }) => Stack(
    children: [
      ViewportHero(
        child: SharedCover(
          tag: controller.selectionMode
              ? null
              : 'playback-${controller.programme.id}/${controller.selectedDate!.id}/${item.id}',
          url: item.cover ?? controller.programme.cover,
          radius: fullEpisode ? 12 : 10,
          aspectRatio: fullEpisode ? 16 / 9 : 4 / 3,
        ),
      ),
      if (playable || controller.selectionMode)
        Positioned(
          right: fullEpisode ? 12 : 6,
          bottom: fullEpisode ? 12 : 6,
          child: Container(
            width: fullEpisode ? 40 : 28,
            height: fullEpisode ? 40 : 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .94),
            ),
            child: Icon(
              controller.selectionMode
                  ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                  : Icons.play_arrow_rounded,
              color: playable
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).disabledColor,
              size: fullEpisode ? 24 : 18,
            ),
          ),
        ),
    ],
  );
}

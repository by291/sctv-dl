import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/pending_update_notice.dart';
import '../../design/state_panel.dart';
import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_policy.dart';
import 'archive_controller.dart';
import 'components/archive_content_card.dart';
import 'components/archive_header.dart';
import 'components/broadcast_date_sheet.dart';
import 'components/broadcast_dates.dart';
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

    controller.restoreSort(_restoredAscending.value);
    unawaited(
      controller.initialize(dateId: dateId).then((_) {
        if (!mounted) return;

        if (!_interacted &&
            restoredMode &&
            controller.selectedDate?.id == dateId) {
          controller.restoreSelection(restoredIds);
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
        if (widget.library.favouriteError case final favouriteError?)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            sliver: SliverToBoxAdapter(
              child: CachedErrorBanner(
                message: favouriteError,
                onRetry: () => unawaited(widget.library.retryFavourites()),
              ),
            ),
          ),
        if (!controller.selectionMode)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ArchiveHeader(
                programme: controller.programme,
                favourite: widget.library.favourites.contains(
                  controller.programme.id,
                ),
                onFavourite: () => unawaited(
                  widget.library.toggleFavourite(controller.programme.id),
                ),
                scroll: _scroll,
                coverTag: widget.coverTag,
              ),
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

  Widget _contentCard(ProgrammeContent item, {required bool fullEpisode}) {
    final broadcast = controller.selectedDate!;
    final card = ArchiveContentCard(
      item: item,
      programme: controller.programme,
      broadcast: broadcast,
      fullEpisode: fullEpisode,
      selected: controller.selectedIds.contains(item.id),
      selectionMode: controller.selectionMode,
      onTap: () {
        if (controller.selectionMode) {
          _action(() => controller.toggleSelection(item))();
        } else {
          widget.onPlay(
            ProgrammeSelection(
              programme: controller.programme,
              broadcast: broadcast,
              content: item,
            ),
          );
        }
      },
    );

    final first =
        controller.fullEpisodes.firstOrNull ?? controller.clips.firstOrNull;

    return item.id == first?.id
        ? CompositedTransformTarget(link: _updateNoticeAnchor, child: card)
        : card;
  }
}

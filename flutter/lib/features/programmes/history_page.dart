import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/primary_page_scaffold.dart';
import '../../design/state_panel.dart';
import '../../domain/playback/history_repository.dart';
import 'components/history_card.dart';

/// Keeps presentation state across visits for the lifetime of the app router.
class HistoryViewState {
  String query = '';
  bool searchOpen = false;
  double scrollOffset = 0;
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.history,
    required this.viewState,
    required this.onOpen,
  });

  final HistoryRepository history;
  final HistoryViewState viewState;
  final ValueChanged<ViewingEntry> onOpen;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with RestorationMixin {
  late final _query = RestorableString(widget.viewState.query);
  late final _searchOpen = RestorableBool(widget.viewState.searchOpen);

  late final _scroll = ScrollController(
    initialScrollOffset: widget.viewState.scrollOffset,
  )..addListener(_rememberScroll);
  final _search = TextEditingController();
  final _focus = FocusNode();

  final _removingHistory = <String>{};
  late final _historyChanges = widget.history.watchHistory();

  @override
  String get restorationId => 'viewing-history-page';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_query, 'query');
    registerForRestoration(_searchOpen, 'search-open');

    _search.text = _query.value;
    widget.viewState.query = _query.value;
    widget.viewState.searchOpen = _searchOpen.value;
  }

  void _rememberScroll() => widget.viewState.scrollOffset = _scroll.offset;

  void _closeSearch() {
    setState(() {
      _query.value = '';
      _searchOpen.value = false;
      widget.viewState.query = '';
      widget.viewState.searchOpen = false;
      _search.clear();
    });

    _focus.unfocus();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _focus.dispose();

    _query.dispose();
    _searchOpen.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PrimaryPageScaffold(
    scrollBehindToolbar: true,
    appBar: AppBar(
      toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 88 : 64,
      title: _searchOpen.value
          ? TextField(
              controller: _search,
              focusNode: _focus,
              decoration: const InputDecoration(
                hintText: '搜索观看记录',
                border: InputBorder.none,
              ),
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() {
                _query.value = value;
                widget.viewState.query = value;
              }),
              onSubmitted: (_) => _focus.unfocus(),
            )
          : const Text('观看历史'),
      actions: [
        IconButton(
          tooltip: _searchOpen.value ? '关闭搜索' : '搜索观看记录',
          icon: Icon(_searchOpen.value ? Icons.close : Icons.search),
          onPressed: () {
            if (_searchOpen.value) {
              _closeSearch();
              return;
            }

            setState(() {
              _searchOpen.value = true;
              widget.viewState.searchOpen = true;
            });
            _focus.requestFocus();
          },
        ),
      ],
    ),
    bodyBuilder: (context, insets) => SafeArea(
      top: false,
      bottom: !usesIosGlass(context),
      child: _history(insets),
    ),
  );

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

  Widget _emptyState(Widget child, EdgeInsets insets) => Padding(
    padding: insets,
    child: CustomScrollView(
      slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
    ),
  );

  Widget _history(EdgeInsets insets) => StreamBuilder<List<ViewingEntry>>(
    stream: _historyChanges,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _emptyState(
          StatePanel(title: '观看记录读取失败', message: '${snapshot.error}'),
          insets,
        );
      }
      if (!snapshot.hasData) {
        return Padding(padding: insets, child: const PageSkeleton());
      }

      final query = _query.value.trim().toLowerCase();
      final items = snapshot.data!
          .where(
            (entry) =>
                '${entry.selection.programme.name} ${entry.selection.content.title}'
                    .toLowerCase()
                    .contains(query),
          )
          .toList();

      if (items.isEmpty && query.isNotEmpty) {
        return _emptyState(
          StatePanel(
            title: '没有匹配的观看记录',
            message: '试试节目名称，或清除搜索查看全部记录。',
            icon: Icons.search_off_rounded,
            actionLabel: '清除搜索',
            onAction: _closeSearch,
          ),
          insets,
        );
      }
      if (items.isEmpty) {
        return _emptyState(
          const StatePanel(
            title: '暂无观看记录',
            message: '观看节目后，可以在这里继续播放。',
            icon: Icons.history,
          ),
          insets,
        );
      }

      final rows = _groupHistory(items, DateTime.now());
      final rowIndices = {
        for (var index = 0; index < rows.length; index++)
          rows[index].entry.selection.ref.key: index,
      };

      return ListView.separated(
        controller: _scroll,
        restorationId: 'viewing-history',
        padding: EdgeInsets.fromLTRB(
          16,
          16 + insets.top,
          16,
          16 + insets.bottom,
        ),
        itemCount: rows.length,
        findItemIndexCallback: (key) =>
            key is ValueKey<String> ? rowIndices[key.value] : null,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final row = rows[index];
          final entry = row.entry;

          return Column(
            key: ValueKey(entry.selection.ref.key),
            children: [
              if (row.heading case final heading?)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(4, index == 0 ? 0 : 8, 4, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Semantics(
                          header: true,
                          child: Text(
                            heading,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              HistoryCard(
                entry: entry,
                onOpen: () => widget.onOpen(entry),
                onRemove: _removingHistory.contains(entry.selection.ref.key)
                    ? null
                    : () => unawaited(_removeHistory(entry)),
              ),
            ],
          );
        },
      );
    },
  );
}

List<({String? heading, ViewingEntry entry})> _groupHistory(
  List<ViewingEntry> entries,
  DateTime now,
) {
  final today = DateUtils.dateOnly(now.toLocal());
  // Calendar arithmetic keeps yesterday correct across daylight-saving changes.
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final groups = <String, List<ViewingEntry>>{'今天': [], '昨天': [], '更早': []};

  final sorted = [...entries]
    ..sort((a, b) {
      final time = b.viewedAt.compareTo(a.viewedAt);
      return time == 0
          ? a.selection.ref.key.compareTo(b.selection.ref.key)
          : time;
    });

  for (final entry in sorted) {
    final day = entry.viewedAt.toLocal();
    final label = DateUtils.isSameDay(day, today)
        ? '今天'
        : DateUtils.isSameDay(day, yesterday)
        ? '昨天'
        : '更早';
    groups[label]!.add(entry);
  }

  return [
    for (final group in groups.entries)
      for (var index = 0; index < group.value.length; index++)
        (heading: index == 0 ? group.key : null, entry: group.value[index]),
  ];
}

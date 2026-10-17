import 'package:flutter/material.dart';

import '../../../domain/programmes/programme.dart';

class BroadcastDates extends StatefulWidget {
  const BroadcastDates({
    super.key,
    required this.dates,
    required this.selected,
    required this.onSelected,
    required this.onMore,
  });

  final List<BroadcastDate> dates;
  final BroadcastDate? selected;
  final ValueChanged<BroadcastDate> onSelected;
  final VoidCallback onMore;

  @override
  State<BroadcastDates> createState() => _BroadcastDatesState();
}

class _BroadcastDatesState extends State<BroadcastDates> {
  final _selectedKey = GlobalKey();

  (double, TextScaler)? _layout;

  @override
  void didUpdateWidget(BroadcastDates oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected?.id != widget.selected?.id ||
        oldWidget.dates != widget.dates) {
      _revealSelection();
    }
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _selectedKey.currentContext;
      final target = context?.findRenderObject();
      if (context == null || target == null) return;
      // Reveal only the horizontal shortcut; keep the archive's vertical position.
      Scrollable.of(context, axis: Axis.horizontal).position.ensureVisible(
        target,
        alignment: .5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = (constraints.maxWidth, MediaQuery.textScalerOf(context));
      if (_layout != layout) {
        _layout = layout;
        _revealSelection();
      }
      return _content(context);
    },
  );

  Widget _content(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    final typography = Theme.of(context).textTheme;
    final sorted = [...widget.dates]..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(7).toList();
    final selected = widget.selected;
    if (selected != null && !recent.any((date) => date.id == selected.id)) {
      recent.add(selected);
      recent.sort((a, b) => b.date.compareTo(a.date));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: Text('播出日期', style: typography.titleMedium)),
              TextButton.icon(
                onPressed: widget.dates.isEmpty ? null : widget.onMore,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('更多日期'),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final date in recent)
                Padding(
                  key: date.id == selected?.id
                      ? _selectedKey
                      : ValueKey(date.id),
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    label: '回看${date.date}',
                    child: ChoiceChip(
                      selected: date.id == selected?.id,
                      showCheckmark: false,
                      selectedColor: colours.primaryContainer,
                      backgroundColor: colours.surfaceContainerLow,
                      side: BorderSide(
                        color: date.id == selected?.id
                            ? Colors.transparent
                            : colours.outlineVariant,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      onSelected: (_) => widget.onSelected(date),
                      label: ExcludeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${DateTime.parse(date.date).month}月${DateTime.parse(date.date).day}日',
                              style: typography.labelLarge?.copyWith(
                                color: date.id == selected?.id
                                    ? colours.onPrimaryContainer
                                    : colours.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              const [
                                '周一',
                                '周二',
                                '周三',
                                '周四',
                                '周五',
                                '周六',
                                '周日',
                              ][DateTime.parse(date.date).weekday - 1],
                              style: typography.labelSmall?.copyWith(
                                color: date.id == selected?.id
                                    ? colours.onPrimaryContainer
                                    : colours.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/programmes/programme.dart';

/// A bounded, lazy date list whose initial offset reveals the accepted date.
class BroadcastDateSheet extends StatefulWidget {
  const BroadcastDateSheet({
    super.key,
    required this.dates,
    required this.selectedId,
    required this.onSelected,
  });

  final List<BroadcastDate> dates;
  final String? selectedId;
  final ValueChanged<BroadcastDate> onSelected;

  @override
  State<BroadcastDateSheet> createState() => _BroadcastDateSheetState();
}

class _BroadcastDateSheetState extends State<BroadcastDateSheet> {
  late final List<_DateEntry> _entries;
  ScrollController? _scroll;

  @override
  void initState() {
    super.initState();
    final sorted = [...widget.dates]..sort((a, b) => b.date.compareTo(a.date));
    final months = <String, List<BroadcastDate>>{};
    for (final date in sorted) {
      months.putIfAbsent(date.date.substring(0, 7), () => []).add(date);
    }
    _entries = [
      for (final month in months.entries) ...[
        _MonthHeading(month.key, month.value.length),
        for (var index = 0; index < month.value.length; index++)
          _DateOption(
            month.value[index],
            first: index == 0,
            last: index == month.value.length - 1,
          ),
      ],
    ];
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择播出日期', style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  '仅显示已有节目的日期',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Text('暂无可选播出日期'),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: LayoutBuilder(builder: _buildList),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, BoxConstraints constraints) {
    final typography = Theme.of(context).textTheme;
    final dayStyle = typography.titleSmall!;
    final weekdayStyle = typography.bodyMedium!;
    final monthStyle = typography.titleMedium!;
    final countStyle = typography.labelMedium!;
    Size measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    double dayWidth = 0, weekdayWidth = 0, dayHeight = 0, weekdayHeight = 0;
    double headingWidth = 0, headingHeight = 0, countHeight = 0;
    for (final entry in _entries) {
      switch (entry) {
        case _DateOption():
          final day = measure(entry.label, dayStyle);
          final weekday = measure(entry.weekday, weekdayStyle);
          dayWidth = math.max(dayWidth, day.width);
          weekdayWidth = math.max(weekdayWidth, weekday.width);
          dayHeight = math.max(dayHeight, day.height);
          weekdayHeight = math.max(weekdayHeight, weekday.height);
        case _MonthHeading():
          final month = measure(entry.label, monthStyle);
          final count = measure(entry.countLabel, countStyle);
          headingWidth = math.max(headingWidth, month.width + count.width + 12);
          headingHeight = math.max(headingHeight, month.height);
          countHeight = math.max(countHeight, count.height);
      }
    }
    // Share measured extents with the lazy list and initial positioning. This
    // includes CJK fallback metrics and avoids a post-opening scroll correction.
    final stackedDate =
        dayWidth + weekdayWidth + 12 > constraints.maxWidth - 116;
    final stackedMonth = headingWidth > constraints.maxWidth - 40;
    final rowHeight = math.max(
      56.0,
      (stackedDate
              ? dayHeight + 4 + weekdayHeight
              : math.max(dayHeight, weekdayHeight)) +
          12,
    );
    final monthHeight =
        (stackedMonth
            ? headingHeight + 4 + countHeight
            : math.max(headingHeight, countHeight)) +
        12;
    final extents = [
      for (final entry in _entries)
        switch (entry) {
          _MonthHeading() => monthHeight,
          _DateOption() =>
            rowHeight + (entry.first ? 6 : 0) + (entry.last ? 30 : 0),
        },
    ];
    final totalHeight = extents.fold(0.0, (sum, height) => sum + height);
    final viewportHeight = math.min(totalHeight, constraints.maxHeight);
    final selectedIndex = _entries.indexWhere(
      (entry) => entry is _DateOption && entry.date.id == widget.selectedId,
    );
    final selectedOffset = selectedIndex < 0
        ? 0.0
        : extents.take(selectedIndex).fold(0.0, (sum, height) => sum + height) -
              (viewportHeight - extents[selectedIndex]) / 2;
    _scroll ??= ScrollController(
      initialScrollOffset: selectedOffset.clamp(
        0,
        math.max(0, totalHeight - viewportHeight),
      ),
    );

    return SizedBox(
      height: viewportHeight,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.zero,
        itemCount: _entries.length,
        itemExtentBuilder: (index, _) => extents[index],
        itemBuilder: (context, index) => switch (_entries[index]) {
          final _MonthHeading month => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: stackedMonth
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(month.label, style: monthStyle),
                      const SizedBox(height: 4),
                      Text(
                        month.countLabel,
                        style: countStyle.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(month.label, style: monthStyle),
                      Text(
                        month.countLabel,
                        style: countStyle.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          final _DateOption option => _dateRow(option, rowHeight, stackedDate),
        },
      ),
    );
  }

  Widget _dateRow(_DateOption option, double height, bool stacked) {
    final colours = Theme.of(context).colorScheme;
    final typography = Theme.of(context).textTheme;
    final selected = option.date.id == widget.selectedId;
    final date = Text(
      option.label,
      style: typography.titleSmall?.copyWith(
        color: selected ? colours.onPrimaryContainer : colours.onSurface,
      ),
    );
    final weekday = Text(
      option.weekday,
      style: typography.bodyMedium?.copyWith(
        color: selected ? colours.onPrimaryContainer : colours.onSurfaceVariant,
      ),
    );
    void select() => widget.onSelected(option.date);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, option.last ? 24 : 0),
      child: Material(
        color: colours.surfaceContainerLow,
        borderRadius: BorderRadius.vertical(
          top: option.first ? const Radius.circular(20) : Radius.zero,
          bottom: option.last ? const Radius.circular(20) : Radius.zero,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            6,
            option.first ? 6 : 0,
            6,
            option.last ? 6 : 0,
          ),
          child: Semantics(
            label: '${option.day.year}年${option.label}，${option.weekday}',
            checked: selected,
            inMutuallyExclusiveGroup: true,
            onTap: select,
            child: ExcludeSemantics(
              child: Ink(
                decoration: BoxDecoration(
                  color: selected
                      ? colours.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: select,
                  autofocus: selected,
                  child: SizedBox(
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: stacked
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      date,
                                      const SizedBox(height: 4),
                                      weekday,
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: date),
                                      const SizedBox(width: 12),
                                      weekday,
                                    ],
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 24,
                            color: selected
                                ? colours.primary
                                : colours.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

sealed class _DateEntry {}

class _MonthHeading extends _DateEntry {
  _MonthHeading(this.month, this.count);
  final String month;
  final int count;
  String get label =>
      '${month.substring(0, 4)}年${int.parse(month.substring(5))}月';
  String get countLabel => '$count 个播出日';
}

class _DateOption extends _DateEntry {
  _DateOption(this.date, {required this.first, required this.last})
    : day = DateTime.parse(date.date);
  final BroadcastDate date;
  final DateTime day;
  final bool first;
  final bool last;
  String get label => '${day.month}月${day.day}日';
  String get weekday =>
      const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][day.weekday - 1];
}

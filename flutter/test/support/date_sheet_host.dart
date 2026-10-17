import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sctv_dl_mobile/design/theme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/programmes/components/broadcast_date_sheet.dart';

List<BroadcastDate> dateSheetDates([int count = 120]) => [
  for (var index = 0; index < count; index++)
    BroadcastDate(
      id: '$index',
      date: DateTime(
        2026,
        10,
        17,
      ).subtract(Duration(days: index)).toIso8601String().substring(0, 10),
    ),
];

Widget dateSheetHost({
  required List<BroadcastDate> dates,
  String? selectedId = '80',
  double scale = 1,
  Brightness brightness = Brightness.light,
  ValueChanged<BroadcastDate>? onSelected,
  GlobalKey? capture,
}) => MaterialApp(
  theme: buildAppTheme(brightness),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('zh', 'CN')],
  locale: const Locale('zh', 'CN'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: capture, child: child),
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showModalBottomSheet<BroadcastDate>(
            context: context,
            showDragHandle: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            useSafeArea: true,
            isScrollControlled: true,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            builder: (context) => BroadcastDateSheet(
              dates: dates,
              selectedId: selectedId,
              onSelected: (date) {
                onSelected?.call(date);
                Navigator.pop(context, date);
              },
            ),
          ),
          child: const Text('更多日期'),
        ),
      ),
    ),
  ),
);

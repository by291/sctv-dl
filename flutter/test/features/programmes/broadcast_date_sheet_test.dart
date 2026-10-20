import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/programmes/components/broadcast_date_sheet.dart';

import '../../support/date_sheet_host.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final size in [const Size(320, 640), const Size(840, 800)]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'selected date opens in place at $size $brightness on $platform with large text',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            BroadcastDate? picked;
            await tester.pumpWidget(
              dateSheetHost(
                dates: dateSheetDates(),
                scale: 2,
                platform: platform,
                brightness: brightness,
                onSelected: (date) => picked = date,
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('更多日期'));
            await tester.pump();
            final list = tester.widget<ListView>(find.byType(ListView));
            final initialOffset = list.controller!.offset;
            expect(initialOffset, greaterThan(3000));
            await tester.pumpAndSettle();
            expect(list.controller!.offset, initialOffset);
            final selected = find.text('7月29日').hitTestable();
            expect(selected, findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(picked?.id, '80');
            expect(find.byType(BroadcastDateSheet), findsNothing);
          },
        );
      }
    }
  }

  testWidgets(
    'month groups scroll beneath a fixed heading and select another month',
    (tester) async {
      BroadcastDate? picked;
      await tester.pumpWidget(
        dateSheetHost(
          dates: dateSheetDates(),
          selectedId: '0',
          onSelected: (date) => picked = date,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('更多日期'));
      await tester.pumpAndSettle();
      expect(find.text('2026年10月'), findsOneWidget);
      expect(find.text('17 个播出日'), findsOneWidget);
      final header = tester.getRect(find.text('选择播出日期'));
      await tester.scrollUntilVisible(
        find.text('9月30日'),
        250,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('选择播出日期')), header);
      await tester.tap(find.text('9月30日'));
      await tester.pumpAndSettle();
      expect(picked?.id, '17');
      expect(find.byType(BroadcastDateSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short and empty date sheets use content height and dismiss without selection',
    (tester) async {
      for (final count in [0, 1]) {
        var selections = 0;
        await tester.pumpWidget(
          dateSheetHost(
            dates: dateSheetDates(count),
            selectedId: '0',
            onSelected: (_) => selections++,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('更多日期'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(BroadcastDateSheet)).height,
          lessThan(250),
        );
        if (count == 0) expect(find.text('暂无可选播出日期'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.byType(BroadcastDateSheet), findsNothing);
        expect(selections, 0);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

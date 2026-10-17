import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/theme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/programmes/components/broadcast_dates.dart';

void main() {
  final dates = [
    for (var day = 16; day >= 9; day--)
      BroadcastDate(
        id: '$day',
        date: '2026-10-${day.toString().padLeft(2, '0')}',
      ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('selected weekday has readable contrast in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          home: Scaffold(
            body: BroadcastDates(
              dates: dates,
              selected: dates.first,
              onSelected: (_) {},
              onMore: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selected = find.byWidgetPredicate(
        (widget) => widget is ChoiceChip && widget.selected,
      );
      final weekday = tester.renderObject<RenderParagraph>(
        find.descendant(of: selected, matching: find.text('周五')),
      );
      final foreground = weekday.text.style!.color!.computeLuminance();
      final background = tester
          .widget<ChoiceChip>(selected)
          .selectedColor!
          .computeLuminance();
      final contrast = foreground > background
          ? (foreground + .05) / (background + .05)
          : (background + .05) / (foreground + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets(
    'selected older date remains reachable after the window narrows',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: BroadcastDates(
              dates: dates,
              selected: dates.last,
              onSelected: (_) {},
              onMore: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(320, 800);
      await tester.pumpAndSettle();

      final selected = find.byWidgetPredicate(
        (widget) => widget is ChoiceChip && widget.selected,
      );
      expect(selected.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

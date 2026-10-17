import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/features/programmes/components/broadcast_date_sheet.dart';

import '../test/support/date_sheet_host.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('native date sheet selection and typography $brightness', (
      tester,
    ) async {
      final capture = GlobalKey();
      await tester.pumpWidget(
        dateSheetHost(
          dates: dateSheetDates(),
          selectedId: '17',
          scale: brightness == Brightness.dark ? 2 : 1,
          brightness: brightness,
          capture: capture,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('更多日期'));
      await tester.pump();
      final list = tester.widget<ListView>(find.byType(ListView));
      final initialOffset = list.controller!.offset;
      await tester.pumpAndSettle();
      expect(list.controller!.offset, initialOffset);
      expect(find.text('9月30日').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      binding.reportData ??= <String, Object?>{};
      final shots = binding.reportData!.putIfAbsent(
        'screenshots',
        () => <Object?>[],
      ) as List<Object?>;
      shots.add({
        'screenshotName': 'date-sheet-${brightness.name}',
        'bytes': data!.buffer.asUint8List().toList(),
      });
      await tester.tap(find.text('9月30日'));
      await tester.pumpAndSettle();
      expect(find.byType(BroadcastDateSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/features/programmes/components/programme_card.dart';

import '../test/support/route_harness.dart';

const _frameInterval = Duration(milliseconds: 100);
const _noticeDeadline = Duration(seconds: 8);

/// Check real Snackbar expiry while the archive remains mounted.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('archive download notice expires on the device clock', (
    tester,
  ) async {
    final harness = RouteHarness();
    await harness.mount(tester, '/');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ProgrammeCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('批量下载'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(content.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载所选 1 项'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '流畅'));
    await tester.pumpAndSettle();

    final notice = find.text('已加入 1 项');
    final shortcut = find.text('查看下载');
    expect(notice, findsOneWidget);
    expect(shortcut, findsOneWidget);

    // A live frame clock exercises the timeout and dismiss animation together.
    final elapsed = Stopwatch()..start();
    while (notice.evaluate().isNotEmpty && elapsed.elapsed < _noticeDeadline) {
      await tester.pump(_frameInterval);
    }
    expect(notice, findsNothing);
    expect(shortcut, findsNothing);
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });
}

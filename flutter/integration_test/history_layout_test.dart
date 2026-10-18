import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/design/cover_image.dart';
import 'package:sctv_dl_mobile/design/theme.dart';
import 'package:sctv_dl_mobile/features/programmes/history_page.dart';

import '../test/support/history_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('history native layout $brightness scale=$scale', (
        tester,
      ) async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day, 12);
        final history = MemoryHistory([
          historyEntry(
            id: '1',
            viewedAt: today,
            title: '2026天府书展——在阅读中遇见更丰盈的自己',
          ),
          historyEntry(
            id: '2',
            viewedAt: today.subtract(const Duration(minutes: 5)),
            title: '四川省人大常委会公开征集2027年监督议题建议',
            position: Duration.zero,
            duration: null,
          ),
          historyEntry(
            id: '3',
            viewedAt: DateTime(now.year, now.month, now.day - 1, 12),
            title: '党建引领接诉即办 提升基层治理效能',
            completed: true,
          ),
          historyEntry(
            id: '4',
            viewedAt: DateTime(now.year, now.month, now.day - 2, 12),
            title: '新思想领航四川新实践——汇聚发展新动能',
            position: const Duration(hours: 1, minutes: 2, seconds: 3),
            duration: const Duration(hours: 2),
          ),
        ]);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await history.close();
        });
        final capture = GlobalKey();
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            locale: const Locale('zh', 'CN'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: capture, child: child),
            ),
            home: HistoryPage(
              history: history,
              viewState: HistoryViewState(),
              onOpen: (_) => opened++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('今天'), findsOneWidget);
        expect(find.byType(CoverImage), findsWidgets);
        expect(tester.takeException(), isNull);
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        binding.reportData ??= <String, Object?>{};
        final shots = binding.reportData!.putIfAbsent(
          'screenshots',
          () => <Object?>[],
        ) as List<Object?>;
        shots.add({
          'screenshotName': 'history-${brightness.name}-${scale.toInt()}',
          'bytes': data!.buffer.asUint8List().toList(),
        });
        await tester.tap(find.text('继续观看').hitTestable().first);
        expect(opened, 1);
        await tester.tap(find.byTooltip('更多操作').hitTestable().first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('移除观看记录'));
        await tester.pumpAndSettle();
        expect(history.entries.length, 3);
        expect(opened, 1);
        final scroll = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;
        while (scroll.offset < scroll.position.maxScrollExtent) {
          scroll.jumpTo(
            (scroll.offset + 200).clamp(0, scroll.position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}

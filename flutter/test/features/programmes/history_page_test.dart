import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/features/programmes/history_page.dart';

import '../../support/history_fixture.dart';
import 'pages_test.dart' show host;

void main() {
  testWidgets('history groups by local viewing day and filters empty groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(840, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 1);
    final repository = MemoryHistory([
      historyEntry(
        id: '3',
        viewedAt: DateTime(now.year, now.month, now.day - 2),
      ),
      historyEntry(
        id: '2',
        viewedAt: DateTime(now.year, now.month, now.day - 1, 23).toUtc(),
      ),
      historyEntry(id: '1', viewedAt: today.toUtc()),
    ]);
    addTearDown(repository.close);
    await tester.pumpWidget(
      host(
        HistoryPage(
          history: repository,
          viewState: HistoryViewState(),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['今天', '昨天', '更早']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.text('今天')).dy,
      lessThan(tester.getTopLeft(find.text('新闻片段 1')).dy),
    );
    expect(
      tester.getTopLeft(find.text('新闻片段 1')).dy,
      lessThan(tester.getTopLeft(find.text('昨天')).dy),
    );
    expect(
      tester.getTopLeft(find.text('新闻片段 2')).dy,
      lessThan(tester.getTopLeft(find.text('更早')).dy),
    );
    expect(find.text('四川新闻联播 · 2025-09-26'), findsNWidgets(3));

    await tester.tap(find.byTooltip('搜索观看记录'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '新闻片段 2');
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsNothing);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('更早'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing a visible record keeps scroll and does not open playback',
    (tester) async {
      final repository = MemoryHistory([
        for (var i = 1; i <= 30; i++)
          historyEntry(id: '$i', viewedAt: DateTime(2026, 1, 1, 0, i)),
      ]);
      addTearDown(repository.close);
      var opened = 0;
      final state = HistoryViewState();
      await tester.pumpWidget(
        host(
          HistoryPage(
            history: repository,
            viewState: state,
            onOpen: (_) => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byType(ListView);
      final scroll = tester.widget<ListView>(list).controller!;
      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(list);
      await tester.tap(find.byTooltip('更多操作').hitTestable().first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除观看记录'));
      await tester.pumpAndSettle();
      expect(repository.removals, 1);
      expect(repository.entries, hasLength(29));
      expect(opened, 0);
      expect(scroll.offset, 500);
      expect(state.scrollOffset, 500);
      expect(tester.getRect(list), bounds);
      expect(tester.takeException(), isNull);
    },
  );
}

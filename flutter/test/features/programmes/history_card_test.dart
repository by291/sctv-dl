import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/programmes/components/history_card.dart';

import 'pages_test.dart' show host;

void main() {
  for (final layout in [(320.0, 1.0), (320.0, 2.0), (840.0, 1.0)]) {
    testWidgets('history actions remain independent at layout $layout', (
      tester,
    ) async {
      tester.view.physicalSize = Size(layout.$1, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      var removed = 0;
      final entry = ViewingEntry(
        selection: const ProgrammeSelection(
          programme: Programme(id: '1', name: '四川新闻联播'),
          broadcast: BroadcastDate(id: '2', date: '2026-10-17'),
          content: ProgrammeContent(id: '3', title: '四川新闻联播：今日重要新闻与精彩节目回看'),
        ),
        position: const Duration(minutes: 4),
        viewedAt: DateTime(2026),
      );
      await tester.pumpWidget(
        host(
          Scaffold(
            body: SingleChildScrollView(
              child: HistoryCard(
                entry: entry,
                onOpen: () => opened++,
                onRemove: () => removed++,
              ),
            ),
          ),
          scale: layout.$2,
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byTooltip('移除观看记录'));
      expect(removed, 1);
      expect(opened, 0);
      await tester.tap(find.text(entry.selection.content.title));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

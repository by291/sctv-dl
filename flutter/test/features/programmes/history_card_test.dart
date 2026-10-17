import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/cover_image.dart';
import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/programmes/components/history_card.dart';

import 'pages_test.dart' show host;
import '../../support/history_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'history retains artwork and hour-long status with large text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final completed in [false, true]) {
          var opened = 0;
          await tester.pumpWidget(
            host(
              Scaffold(
                body: SingleChildScrollView(
                  child: HistoryCard(
                    entry: historyEntry(
                      id: '1',
                      viewedAt: DateTime(2026),
                      position: const Duration(
                        hours: 1,
                        minutes: 2,
                        seconds: 3,
                      ),
                      duration: const Duration(hours: 2),
                      completed: completed,
                      title: '四川新闻联播：今日重要新闻与精彩节目回看',
                    ),
                    onOpen: () => opened++,
                    onRemove: null,
                  ),
                ),
              ),
              scale: 2,
              brightness: brightness,
            ),
          );
          final cover = find.byType(CoverImage);
          expect(cover, findsOneWidget);
          final bounds = tester.getRect(cover);
          expect(bounds.width / bounds.height, closeTo(16 / 9, .01));
          expect(
            find.text(completed ? '已看完' : '看到 1:02:03 / 2:00:00'),
            findsOneWidget,
          );
          if (completed) {
            expect(find.byType(LinearProgressIndicator), findsNothing);
          } else {
            final progress = tester.getRect(
              find.byType(LinearProgressIndicator),
            );
            expect(progress.bottom, bounds.bottom);
            expect(progress.width, bounds.width);
          }
          Focus.of(tester.element(find.text(completed ? '再看一次' : '继续观看')))
              .requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(opened, 1);
          await tester.tap(find.byTooltip('更多操作'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<PopupMenuItem<Object?>>(
                  find
                      .byWidgetPredicate((widget) => widget is PopupMenuItem)
                      .first,
                )
                .enabled,
            isFalse,
          );
          Navigator.of(tester.element(find.text('移除观看记录'))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets(
    'unstarted history offers playback without an empty progress bar',
    (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: HistoryCard(
              entry: ViewingEntry(
                selection: const ProgrammeSelection(
                  programme: Programme(id: '1', name: '四川新闻联播'),
                  broadcast: BroadcastDate(id: '2', date: '2026-10-17'),
                  content: ProgrammeContent(id: '3', title: '新闻片段'),
                ),
                position: Duration.zero,
                duration: const Duration(minutes: 4),
                viewedAt: DateTime(2026, 10, 17),
              ),
              onOpen: () {},
              onRemove: () {},
            ),
          ),
        ),
      );
      expect(find.text('尚未播放'), findsOneWidget);
      expect(find.text('播放'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

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
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(removed, 0);
      await tester.tap(find.text('移除观看记录'));
      await tester.pumpAndSettle();
      expect(removed, 1);
      expect(opened, 0);
      await tester.tap(find.text(entry.selection.content.title));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

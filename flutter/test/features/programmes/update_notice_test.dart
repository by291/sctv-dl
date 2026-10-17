import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/pending_update_notice.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';

import '../../support/fakes.dart';
import 'pages_test.dart' show host;

void main() {
  for (final layout in [
    (320.0, 1.0, Brightness.light),
    (320.0, 2.0, Brightness.dark),
    (1100.0, 1.0, Brightness.light),
  ]) {
    testWidgets('library update floats without moving content at $layout', (
      tester,
    ) async {
      tester.view.physicalSize = Size(layout.$1, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final items = [
        for (var i = 1; i <= 30; i++) Programme(id: '$i', name: '栏目 $i'),
      ];
      final repository = FakeProgrammeRepository()
        ..catalogue = snapshot(items, 'old');
      final user = FakeUserRepository();
      final controller = LibraryController(
        repository: repository,
        user: user,
        initialFavourites: {},
      );
      addTearDown(controller.dispose);
      addTearDown(user.close);
      await tester.pumpWidget(
        host(
          LibraryPage(
            controller: controller,
            onOpenProgramme: (_) {},
            onShowHistory: () {},
          ),
          scale: layout.$2,
          brightness: layout.$3,
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byType(CustomScrollView);
      final scroll = tester.widget<CustomScrollView>(list).controller!;
      scroll.jumpTo(160);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(list);
      final card = find.byType(ProgrammeCard).first;
      final cardBounds = tester.getRect(card);
      repository.catalogue = snapshot([
        ...items,
        const Programme(id: '31', name: '新栏目'),
      ], 'new');
      await controller.refresh();
      await tester.pumpAndSettle();

      final notice = find.text('发现新内容');
      expect(notice, findsOneWidget);
      expect(
        tester.getRect(notice).top,
        greaterThan(tester.getRect(find.byType(AppBar)).bottom + 16),
      );
      expect(
        tester.getRect(notice).top,
        greaterThan(tester.getRect(find.text('默认顺序')).bottom + 8),
      );
      expect(tester.getRect(list), bounds);
      expect(tester.getRect(card), cardBounds);
      expect(scroll.offset, 160);
      final target = find.ancestor(
        of: notice,
        matching: find.byType(TextButton),
      );
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(target).left, greaterThanOrEqualTo(16));
      expect(tester.getRect(target).right, lessThanOrEqualTo(layout.$1 - 16));
      expect(controller.programmes.length, 30);
      if (layout.$1 > 1000) {
        Focus.of(tester.element(notice)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        // The compact visual keeps a full-height touch target.
        final rect = tester.getRect(target);
        await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
      }
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      expect(controller.programmes.length, 31);
      expect(scroll.offset, 160);
      expect(tester.getRect(card), cardBounds);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('notice is local to the visible route and retained tab', (
    tester,
  ) async {
    var accepts = 0;
    var contentTaps = 0;
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      host(
        ValueListenableBuilder(
          valueListenable: active,
          builder: (context, enabled, _) => TickerMode(
            enabled: enabled,
            child: Scaffold(
              body: PendingUpdateOverlay(
                visible: true,
                onUpdate: () => accepts++,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => contentTaps++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final notice = find.text('发现新内容');
    await tester.tapAt(const Offset(20, 80));
    expect(contentTaps, 1);
    expect(accepts, 0);
    final navigator = Navigator.of(tester.element(notice));
    // A transparent route exposes any notice incorrectly retained underneath.
    final popped = navigator.push<void>(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => const Center(child: Text('Another page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    navigator.pop();
    await tester.pumpAndSettle();
    await popped;
    expect(notice, findsOneWidget);
    active.value = false;
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    active.value = true;
    await tester.pumpAndSettle();
    await tester.tap(notice);
    expect(accepts, 1);
  });

  testWidgets(
    'archive hides pending updates in selection and retains scroll on acceptance',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const programme = Programme(id: '1', name: '四川新闻');
      final items = [
        for (var i = 1; i <= 20; i++)
          ProgrammeContent(
            id: '$i',
            title: '新闻片段 $i',
            video: 'https://fscgc.scgchc.com/$i.mp4',
          ),
      ];
      final repository = FakeProgrammeRepository()
        ..dates = snapshot([
          const BroadcastDate(id: '2', date: '2026-10-17'),
        ], 'dates')
        ..contents['2'] = snapshot(items, 'old');
      final user = FakeUserRepository();
      final library = LibraryController(
        repository: repository,
        user: user,
        initialFavourites: {},
      );
      final controller = ArchiveController(
        repository: repository,
        programme: programme,
      );
      addTearDown(library.dispose);
      addTearDown(user.close);
      await tester.pumpWidget(
        host(
          ArchivePage(
            controller: controller,
            library: library,
            onPlay: (_) {},
            onDownload: (_) async {},
            onOpenProgramme: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      repository.contents['2'] = snapshot([
        ...items,
        const ProgrammeContent(id: '21', title: '新片段'),
      ], 'new');
      await controller.refresh();
      await tester.pumpAndSettle();
      final notice = find.text('发现新内容');
      expect(notice, findsOneWidget);
      expect(
        tester.getRect(notice).top,
        greaterThan(tester.getRect(find.text('0 个完整节目 · 20 个片段')).bottom + 8),
      );
      final noticeButton = find.ancestor(
        of: notice,
        matching: find.byType(TextButton),
      );
      expect(
        tester.getRect(noticeButton).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('新闻片段 1')).top),
      );
      final noticeTop = tester.getRect(notice).top;
      final initialScroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      initialScroll.jumpTo(20);
      await tester.pumpAndSettle();
      expect(tester.getRect(notice).top, closeTo(noticeTop - 20, .1));
      initialScroll.jumpTo(0);
      await tester.pumpAndSettle();
      controller.enterSelection();
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      expect(controller.hasPendingUpdate, isTrue);
      controller.exitSelection();
      await tester.pumpAndSettle();
      final list = find.byType(CustomScrollView);
      final scroll = tester.widget<CustomScrollView>(list).controller!;
      scroll.jumpTo(240);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(list);
      await tester.tap(notice);
      await tester.pumpAndSettle();
      expect(controller.contents.length, 21);
      expect(notice, findsNothing);
      expect(scroll.offset, 240);
      expect(tester.getRect(list), bounds);
      expect(tester.takeException(), isNull);
    },
  );
}

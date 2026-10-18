import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/cover_image.dart';
import 'package:sctv_dl_mobile/design/theme.dart';
import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/domain/settings/preferences.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/programmes/components/programme_card.dart';
import 'package:sctv_dl_mobile/features/programmes/history_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';
import 'package:sctv_dl_mobile/features/settings/settings_page.dart';

import '../../support/fakes.dart';

class EmptyHistory implements HistoryRepository {
  EmptyHistory({this.entries = const [], this.removeError});
  final List<ViewingEntry> entries;
  final Object? removeError;
  @override
  Future<List<ViewingEntry>> loadHistory() async => entries;
  @override
  Stream<List<ViewingEntry>> watchHistory() => Stream.value(entries);
  @override
  Future<void> save(ViewingEntry entry) async {}
  @override
  Future<void> remove(ContentRef ref) async {
    if (removeError case final error?) throw error;
  }

  @override
  Future<void> clear() async {}
}

Widget host(
  Widget child, {
  double scale = 1,
  Brightness brightness = Brightness.light,
  ThemeData? theme,
}) => ProviderScope(
  child: MaterialApp(
    theme: theme ?? buildAppTheme(brightness),
    restorationScopeId: 'test-app',
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: widget!,
    ),
    home: child,
  ),
);

void main() {
  const programme = Programme(id: '1', name: '四川新闻');
  for (final layout in [(320.0, 1.0), (390.0, 1.3), (840.0, 2.0)]) {
    testWidgets('catalogue fits actual title metrics at $layout', (
      tester,
    ) async {
      tester.view.physicalSize = Size(layout.$1, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final user = FakeUserRepository();
      final controller = LibraryController(
        repository: FakeProgrammeRepository()
          ..catalogue = snapshot(const [
            Programme(id: '1', name: '问您所“？”'),
            Programme(id: '2', name: '四川新闻联播与精彩节目回看'),
          ], 'titles'),
        user: user,
        initialFavourites: {},
      );
      addTearDown(controller.dispose);
      addTearDown(user.close);
      final theme = buildAppTheme(Brightness.light);
      await tester.pumpWidget(
        host(
          LibraryPage(
            controller: controller,
            onOpenProgramme: (_) {},
            onShowHistory: () {},
          ),
          scale: layout.$2,
          theme: theme.copyWith(
            textTheme: theme.textTheme.copyWith(
              titleMedium: theme.textTheme.titleMedium!.copyWith(fontSize: 18),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final item in controller.programmes) {
        final card = find.byWidgetPredicate(
          (widget) => widget is ProgrammeCard && widget.programme.id == item.id,
        );
        await tester.ensureVisible(card);
        final title = find.descendant(of: card, matching: find.text(item.name));
        expect(
          tester.getRect(title).bottom,
          lessThanOrEqualTo(tester.getRect(card).bottom - 9),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'history search can recover and removal failures keep playback available',
    (tester) async {
      final entry = ViewingEntry(
        selection: const ProgrammeSelection(
          programme: programme,
          broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
          content: ProgrammeContent(id: '3', title: '晚间新闻'),
        ),
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 20),
        viewedAt: DateTime(2026, 10, 17),
      );
      ViewingEntry? opened;
      await tester.pumpWidget(
        host(
          HistoryPage(
            viewState: HistoryViewState(),
            history: EmptyHistory(
              entries: [entry],
              removeError: StateError('storage unavailable'),
            ),
            onOpen: (value) => opened = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索观看记录'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pumpAndSettle();
      expect(find.text('暂无观看记录'), findsNothing);
      await tester.tap(find.text('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .2,
      );
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除观看记录'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('晚间新闻'));
      expect(opened, same(entry));
    },
  );

  testWidgets(
    'favourites only filters the list and leaves the exploration in place',
    (tester) async {
      final repository = FakeProgrammeRepository()
        ..catalogue = snapshot([programme], 'one');
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
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TabBar), findsNothing);
      final exploration = tester.getRect(find.text('栏目探索'));
      final featured = controller.featured;
      await tester.tap(find.byTooltip('只看收藏'));
      await tester.pumpAndSettle();
      expect(find.text('还没有收藏'), findsOneWidget);
      expect(tester.getRect(find.text('栏目探索')), exploration);
      expect(controller.featured, same(featured));
      expect(find.text('查看节目'), findsOneWidget);
      await tester.tap(find.byTooltip('显示全部栏目'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammeCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filter transition keeps outgoing cards until the empty state appears',
    (tester) async {
      final user = FakeUserRepository();
      final controller = LibraryController(
        repository: FakeProgrammeRepository()
          ..catalogue = snapshot([programme], 'one'),
        user: user,
        initialFavourites: {},
      );
      addTearDown(user.close);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          LibraryPage(
            controller: controller,
            onOpenProgramme: (_) {},
            onShowHistory: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(60);
      await tester.pump();
      final top = tester.getRect(find.text('栏目探索'));
      await tester.tap(find.byTooltip('只看收藏'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(ProgrammeCard), findsOneWidget);
      expect(find.text('还没有收藏'), findsOneWidget);
      expect(tester.getRect(find.text('栏目探索')), top);
      expect(scroll.offset, 60);
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammeCard), findsNothing);
      expect(tester.getRect(find.text('栏目探索')), top);
      expect(scroll.offset, 60);
    },
  );

  testWidgets(
    'shuffling long titles keeps exploration actions at the same position',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final user = FakeUserRepository();
      final controller = LibraryController(
        repository: FakeProgrammeRepository()
          ..catalogue = snapshot([
            programme,
            const Programme(id: '2', name: '四川新闻联播与精彩节目回看特别报道'),
          ], 'one'),
        user: user,
        initialFavourites: {},
      )..featuredId = '1';
      addTearDown(user.close);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          LibraryPage(
            controller: controller,
            onOpenProgramme: (_) {},
            onShowHistory: () {},
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.getRect(find.text('换一个'));
      await tester.tap(find.text('换一个'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(find.text('换一个')), button);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('换一个')), button);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('catalogue transitions retain lazy grid construction', (
    tester,
  ) async {
    final user = FakeUserRepository();
    final controller = LibraryController(
      repository: FakeProgrammeRepository()
        ..catalogue = snapshot([
          for (var i = 0; i < 1000; i++) Programme(id: '$i', name: '栏目 $i'),
        ], 'many'),
      user: user,
      initialFavourites: {},
    );
    addTearDown(user.close);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        LibraryPage(
          controller: controller,
          onOpenProgramme: (_) {},
          onShowHistory: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProgrammeCard).evaluate().length, lessThan(100));
    expect(find.byType(ProgrammeCard), findsWidgets);
    await tester.tap(find.byTooltip('只看收藏'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(ProgrammeCard).evaluate().length, lessThan(100));
    await tester.pumpAndSettle();
    expect(find.byType(ProgrammeCard), findsNothing);
  });

  testWidgets('rapid search toggles retain a single input and keyboard focus', (
    tester,
  ) async {
    final user = FakeUserRepository();
    final controller = LibraryController(
      repository: FakeProgrammeRepository()
        ..catalogue = snapshot([programme], 'one'),
      user: user,
      initialFavourites: {},
    );
    addTearDown(user.close);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        LibraryPage(
          controller: controller,
          onOpenProgramme: (_) {},
          onShowHistory: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('搜索栏目'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
      await tester.tap(find.byTooltip('关闭搜索'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.tap(find.byTooltip('搜索栏目'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '四川');
    expect(controller.query, '四川');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final layout in [(320.0, 1.0), (320.0, 2.0), (840.0, 1.0)]) {
    testWidgets(
      'favourite stays independent of opening a programme at layout $layout',
      (tester) async {
        tester.view.physicalSize = Size(layout.$1, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const longProgramme = Programme(id: '1', name: '四川新闻联播与精彩节目回看');
        final repository = FakeProgrammeRepository()
          ..catalogue = snapshot([longProgramme], 'one');
        final user = FakeUserRepository();
        final controller = LibraryController(
          repository: repository,
          user: user,
          initialFavourites: {},
        );
        addTearDown(controller.dispose);
        addTearDown(user.close);
        var opened = 0;
        await tester.pumpWidget(
          host(
            LibraryPage(
              controller: controller,
              onOpenProgramme: (_) => opened++,
              onShowHistory: () {},
            ),
            scale: layout.$2,
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final favourite = find.byTooltip('收藏 ${longProgramme.name}');
        await tester.ensureVisible(favourite);
        // The surrounding artwork, including the circle's square corners,
        // opens the programme instead of toggling its favourite state.
        await tester.tapAt(tester.getCenter(favourite) + const Offset(20, 0));
        await tester.pumpAndSettle();
        expect(controller.favourites, isEmpty);
        expect(opened, 1);
        await tester.tapAt(tester.getCenter(favourite) + const Offset(14, 14));
        await tester.pumpAndSettle();
        expect(controller.favourites, isEmpty);
        expect(opened, 2);
        await tester.tap(favourite);
        await tester.pumpAndSettle();
        expect(controller.favourites, contains('1'));
        expect(opened, 2);
        final title = find.descendant(
          of: find.byType(ProgrammeCard),
          matching: find.text(longProgramme.name),
        );
        await tester.ensureVisible(title);
        await tester.tap(title);
        expect(opened, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the full date chooser is reachable and keeps an older selection visible',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeProgrammeRepository()
        ..dates = snapshot([
          for (var day = 16; day >= 9; day--)
            BroadcastDate(
              id: '$day',
              date: '2026-10-${day.toString().padLeft(2, '0')}',
            ),
        ], 'dates');
      for (var day = 16; day >= 9; day--) {
        repository.contents['$day'] = snapshot([
          for (var index = 1; index <= 20; index++)
            ProgrammeContent(id: '$index', title: '新闻片段 $index'),
        ], 'contents');
      }
      final user = FakeUserRepository();
      addTearDown(user.close);
      final library = LibraryController(
        repository: repository,
        user: user,
        initialFavourites: {},
      );
      addTearDown(library.dispose);
      final archive = ArchiveController(
        repository: repository,
        programme: programme,
      );
      await tester.pumpWidget(
        host(
          ArchivePage(
            controller: archive,
            library: library,
            onPlay: (_) {},
            onDownload: (_) async {},
            onOpenProgramme: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final more = find.text('更多日期').hitTestable();
      expect(more, findsOneWidget);
      final list = find.byType(CustomScrollView);
      final scroll = tester.widget<CustomScrollView>(list).controller!;
      scroll.jumpTo(60);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(list);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('2026年10月'), findsOneWidget);
      expect(find.text('8 个播出日'), findsOneWidget);
      final older = find.text('10月9日');
      await tester.scrollUntilVisible(
        older,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(older);
      await tester.pumpAndSettle();

      expect(archive.selectedDate?.id, '9');
      expect(find.text('选择播出日期'), findsNothing);
      expect(scroll.offset, 60);
      expect(tester.getRect(list), viewport);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('10月9日').hitTestable(), findsOneWidget);
      Navigator.of(tester.element(find.text('选择播出日期'))).pop();
      await tester.pumpAndSettle();
      expect(scroll.offset, 60);
      expect(tester.getRect(list), viewport);
      final selected = find.byWidgetPredicate(
        (widget) => widget is ChoiceChip && widget.selected,
      );
      expect(selected.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('favourites preserves the current search and sort', (
    tester,
  ) async {
    final repository = FakeProgrammeRepository()
      ..catalogue = snapshot([
        programme,
        const Programme(id: '2', name: '音乐现场'),
      ], 'one');
    final user = FakeUserRepository()..favourites = {'1'};
    final controller = LibraryController(
      repository: repository,
      user: user,
      initialFavourites: {'1'},
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
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索栏目'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pump();
    expect(find.text('没有找到相关栏目'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('默认顺序'));
    await tester.pump();
    await tester.tap(find.byTooltip('只看收藏'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关栏目'), findsOneWidget);
    expect(find.text('名称排序'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '不存在',
    );
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byTooltip('显示全部栏目'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关栏目'), findsOneWidget);
    expect(find.text('名称排序'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '不存在',
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('batch selection retains artwork at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const episode = ProgrammeContent(
        id: '3',
        title: '四川新闻（2026.10.16）',
        video: 'https://fscgc.scgchc.com/a.mp4',
      );
      const clip = ProgrammeContent(
        id: '4',
        title: '新闻片段',
        video: 'https://fscgc.scgchc.com/b.mp4',
      );
      final repository = FakeProgrammeRepository()
        ..dates = snapshot([
          const BroadcastDate(id: '2', date: '2026-10-16'),
        ], 'dates')
        ..contents['2'] = snapshot([episode, clip], 'contents');
      final user = FakeUserRepository();
      final library = LibraryController(
        repository: repository,
        user: user,
        initialFavourites: {},
      );
      final archive = ArchiveController(
        repository: repository,
        programme: programme,
      );
      addTearDown(user.close);
      addTearDown(library.dispose);
      var played = false;
      await tester.pumpWidget(
        host(
          ArchivePage(
            controller: archive,
            library: library,
            onPlay: (_) => played = true,
            onDownload: (_) async {},
            onOpenProgramme: (_) {},
          ),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      Finder card(ProgrammeContent item) =>
          find.ancestor(of: find.text(item.title), matching: find.byType(Card));
      Finder cover(ProgrammeContent item) =>
          find.descendant(of: card(item), matching: find.byType(CoverImage));
      final sizes = <String, Size>{};
      for (final item in [episode, clip]) {
        await tester.ensureVisible(find.text(item.title));
        expect(cover(item), findsOneWidget);
        sizes[item.id] = tester.getSize(cover(item));
      }
      archive.enterSelection();
      await tester.pumpAndSettle();
      for (final item in [episode, clip]) {
        await tester.ensureVisible(find.text(item.title));
        expect(cover(item), findsOneWidget);
        expect(tester.getSize(cover(item)), sizes[item.id]);
        await tester.tap(cover(item));
        await tester.pump();
        expect(archive.selectedIds, contains(item.id));
      }
      expect(played, isFalse);
      archive.exitSelection();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(clip.title));
      await tester.tap(cover(clip));
      expect(played, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'archive batch back exits selection and large text keeps all content reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeProgrammeRepository()
        ..dates = snapshot([
          const BroadcastDate(id: '2', date: '2026-10-16'),
        ], 'dates')
        ..contents['2'] = snapshot([
          const ProgrammeContent(
            id: '3',
            title: '四川新闻（2026.10.16）',
            video: 'https://fscgc.scgchc.com/a.mp4',
          ),
          const ProgrammeContent(
            id: '4',
            title: '这是一个很长的节目片段标题，用来验证大字体布局仍能完整阅读',
            video: 'https://fscgc.scgchc.com/b.mp4',
          ),
        ], 'contents');
      final user = FakeUserRepository();
      addTearDown(user.close);
      final library = LibraryController(
        repository: repository,
        user: user,
        initialFavourites: {},
      );
      addTearDown(library.dispose);
      final archive = ArchiveController(
        repository: repository,
        programme: programme,
      );
      await tester.pumpWidget(
        host(
          ArchivePage(
            controller: archive,
            library: library,
            onPlay: (_) {},
            onDownload: (_) async {},
            onOpenProgramme: (_) {},
          ),
          scale: 2,
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('批量下载'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('下载所选 2 项'), findsOneWidget);
      await tester.tap(find.byTooltip('退出批量选择'));
      await tester.pumpAndSettle();
      expect(find.text('下载所选 2 项'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'process restoration retains search without reopening the keyboard',
    (tester) async {
      final repository = FakeProgrammeRepository()
        ..catalogue = snapshot([programme], 'one');
      final user = FakeUserRepository();
      addTearDown(user.close);
      await tester.pumpWidget(
        host(_RestorableLibrary(repository: repository, user: user)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索栏目'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pump();
      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('没有找到相关栏目'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
    },
  );

  testWidgets(
    'process restoration keeps the broadcast and valid batch selection',
    (tester) async {
      final repository = FakeProgrammeRepository()
        ..dates = snapshot([
          const BroadcastDate(id: '2', date: '2026-10-16'),
          const BroadcastDate(id: '5', date: '2026-10-15'),
        ], 'dates')
        ..contents['2'] = snapshot([
          const ProgrammeContent(
            id: '3',
            title: 'First',
            video: 'https://fscgc.scgchc.com/a.mp4',
          ),
        ], 'first')
        ..contents['5'] = snapshot([
          const ProgrammeContent(
            id: '6',
            title: 'Older',
            video: 'https://fscgc.scgchc.com/b.mp4',
          ),
        ], 'older');
      final user = FakeUserRepository();
      addTearDown(user.close);
      await tester.pumpWidget(
        host(_RestorableArchive(repository: repository, user: user)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '10月15日'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('批量下载'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      expect(find.text('Older'), findsOneWidget);
      expect(find.text('First'), findsNothing);
    },
  );

  testWidgets(
    'theme chooser reports the selected preference without requiring a restart',
    (tester) async {
      Preferences? changed;
      await tester.pumpWidget(
        host(
          SettingsPage(
            preferences: const Preferences(),
            onChanged: (value) async {
              changed = value;
            },
            onClearCache: () async {},
            onClearHistory: () async {},
            version: '0.1.0 (1)',
          ),
        ),
      );
      await tester.tap(find.text('主题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(changed?.theme, AppThemeMode.dark);
    },
  );
}

class _RestorableLibrary extends StatefulWidget {
  const _RestorableLibrary({required this.repository, required this.user});
  final FakeProgrammeRepository repository;
  final FakeUserRepository user;
  @override
  State<_RestorableLibrary> createState() => _RestorableLibraryState();
}

class _RestorableLibraryState extends State<_RestorableLibrary> {
  late final controller = LibraryController(
    repository: widget.repository,
    user: widget.user,
    initialFavourites: {},
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LibraryPage(
    controller: controller,
    onOpenProgramme: (_) {},
    onShowHistory: () {},
  );
}

class _RestorableArchive extends StatefulWidget {
  const _RestorableArchive({required this.repository, required this.user});
  final FakeProgrammeRepository repository;
  final FakeUserRepository user;
  @override
  State<_RestorableArchive> createState() => _RestorableArchiveState();
}

class _RestorableArchiveState extends State<_RestorableArchive> {
  late final library = LibraryController(
    repository: widget.repository,
    user: widget.user,
    initialFavourites: {},
  );
  late final archive = ArchiveController(
    repository: widget.repository,
    programme: const Programme(id: '1', name: '四川新闻'),
  );
  @override
  void dispose() {
    library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchivePage(
    controller: archive,
    library: library,
    onPlay: (_) {},
    onDownload: (_) async {},
    onOpenProgramme: (_) {},
  );
}

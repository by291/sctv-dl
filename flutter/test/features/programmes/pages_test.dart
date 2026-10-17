import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/theme.dart';
import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';
import 'package:sctv_dl_mobile/features/settings/settings_page.dart';
import 'package:sctv_dl_mobile/domain/settings/preferences.dart';

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
}) => ProviderScope(
  child: MaterialApp(
    theme: buildAppTheme(brightness),
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
      ViewingEntry? opened;
      await tester.pumpWidget(
        host(
          LibraryPage(
            controller: controller,
            history: EmptyHistory(
              entries: [entry],
              removeError: StateError('storage unavailable'),
            ),
            onOpenProgramme: (_) {},
            onOpenHistory: (value) => opened = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('最近观看'));
      await tester.pumpAndSettle();
      controller.setQuery(LibraryTab.history, '不存在');
      await tester.pumpAndSettle();
      expect(find.text('暂无观看记录'), findsNothing);
      await tester.tap(find.text('清除搜索'));
      await tester.pumpAndSettle();
      expect(controller.query(LibraryTab.history), isEmpty);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .2,
      );
      await tester.tap(find.byTooltip('移除观看记录'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('晚间新闻'));
      expect(opened, same(entry));
    },
  );

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
              history: EmptyHistory(),
              onOpenProgramme: (_) => opened++,
              onOpenHistory: (_) {},
            ),
            scale: layout.$2,
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final favourite = find.byTooltip('收藏 ${longProgramme.name}');
        await tester.ensureVisible(favourite);
        await tester.tap(favourite);
        await tester.pumpAndSettle();

        expect(controller.favourites, contains('1'));
        expect(opened, 0);
        final title = find.descendant(
          of: find.byType(ProgrammeCard),
          matching: find.text(longProgramme.name),
        );
        await tester.ensureVisible(title);
        await tester.tap(title);
        expect(opened, 1);
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
      await tester.tap(more);
      await tester.pumpAndSettle();
      final older = find.text('2026-10-09');
      await tester.scrollUntilVisible(
        older,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(older);
      await tester.pumpAndSettle();

      expect(archive.selectedDate?.id, '9');
      expect(find.text('选择播出日期'), findsNothing);
      final selected = find.byWidgetPredicate(
        (widget) => widget is ChoiceChip && widget.selected,
      );
      expect(selected.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search keeps focus and tab filters do not leak into favourites',
    (tester) async {
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
            history: EmptyHistory(),
            onOpenProgramme: (_) {},
            onOpenHistory: (_) {},
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
      await tester.tap(find.text('我的收藏'));
      await tester.pumpAndSettle();
      expect(find.text('四川新闻'), findsWidgets);
      expect(find.text('没有找到相关栏目'), findsNothing);
    },
  );

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
    history: EmptyHistory(),
    onOpenProgramme: (_) {},
    onOpenHistory: (_) {},
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

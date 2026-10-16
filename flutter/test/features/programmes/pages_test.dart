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
  @override
  Future<List<ViewingEntry>> loadHistory() async => [];
  @override
  Stream<List<ViewingEntry>> watchHistory() => Stream.value([]);
  @override
  Future<void> save(ViewingEntry entry) async {}
  @override
  Future<void> remove(ContentRef ref) async {}
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
      await tester.tap(find.text('2026-10-15'));
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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/design/theme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';

import '../test/support/fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final archive in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets('floating update native layout archive=$archive $brightness', (
        tester,
      ) async {
        final items = [
          for (var i = 1; i <= 30; i++) Programme(id: '$i', name: '四川新闻栏目 $i'),
        ];
        final clips = [
          for (var i = 1; i <= 30; i++)
            ProgrammeContent(id: '$i', title: '新闻片段 $i'),
        ];
        final repository = FakeProgrammeRepository()
          ..catalogue = snapshot(items, 'old')
          ..dates = snapshot([
            const BroadcastDate(id: '2', date: '2026-10-17'),
          ], 'dates')
          ..contents['2'] = snapshot(clips, 'old');
        final user = FakeUserRepository();
        final library = LibraryController(
          repository: repository,
          user: user,
          initialFavourites: {},
        );
        final controller = archive
            ? ArchiveController(repository: repository, programme: items.first)
            : null;
        final capture = GlobalKey();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          library.dispose();
          await user.close();
        });
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: buildAppTheme(brightness),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('zh', 'CN')],
              locale: const Locale('zh', 'CN'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    brightness == Brightness.dark ? 2 : 1,
                  ),
                ),
                child: RepaintBoundary(key: capture, child: child),
              ),
              home: archive
                  ? ArchivePage(
                      controller: controller!,
                      library: library,
                      onPlay: (_) {},
                      onDownload: (_) async {},
                      onOpenProgramme: (_) {},
                    )
                  : LibraryPage(
                      controller: library,
                      onOpenProgramme: (_) {},
                      onShowHistory: () {},
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byType(CustomScrollView);
        final scroll = tester.widget<CustomScrollView>(list).controller!;
        scroll.jumpTo(160);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(list);
        repository.catalogue = snapshot([
          ...items,
          const Programme(id: '31', name: '新栏目'),
        ], 'new');
        repository.contents['2'] = snapshot([
          ...clips,
          const ProgrammeContent(id: '31', title: '新节目'),
        ], 'new');
        if (archive) {
          await controller!.refresh();
        } else {
          await library.refresh();
        }
        await tester.pumpAndSettle();
        expect(find.text('发现新内容'), findsOneWidget);
        expect(scroll.offset, 160);
        expect(tester.getRect(list), bounds);
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
          'screenshotName':
              'update-notice-${archive ? "archive" : "library"}-${brightness.name}',
          'bytes': data!.buffer.asUint8List().toList(),
        });
        if (archive) {
          controller!.enterSelection();
          await tester.pumpAndSettle();
          expect(find.text('发现新内容'), findsNothing);
          controller.exitSelection();
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('发现新内容'));
        await tester.pumpAndSettle();
        expect(find.text('发现新内容'), findsNothing);
        expect(scroll.offset, 160);
        expect(tester.getRect(list), bounds);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

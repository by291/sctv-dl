import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/design/theme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/programmes/library_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';

import '../test/support/fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const names = ['问您所“？”', '四川新闻联播', '乡村大篷车', '四川新闻联播与精彩节目回看'];

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('catalogue native typography $brightness scale=$scale', (
        tester,
      ) async {
        final user = FakeUserRepository();
        final controller = LibraryController(
          repository: FakeProgrammeRepository()
            ..catalogue = snapshot([
              for (var i = 0; i < 20; i++)
                Programme(id: '$i', name: names[i % names.length]),
            ], 'native-layout'),
          user: user,
          initialFavourites: {},
        );
        final capture = GlobalKey();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
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
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: capture, child: child),
              ),
              home: LibraryPage(
                controller: controller,
                onOpenProgramme: (_) {},
                onShowHistory: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        while (true) {
          expect(tester.takeException(), isNull);
          for (final card in tester.elementList(find.byType(ProgrammeCard))) {
            final title = find.descendant(
              of: find.byElementPredicate((element) => element == card),
              matching: find.byType(Text),
            );
            final cardBounds = tester.getRect(
              find.byElementPredicate((element) => element == card),
            );
            expect(
              tester.getRect(title).bottom,
              lessThanOrEqualTo(cardBounds.bottom - 9),
            );
          }
          if (scroll.position.pixels >= scroll.position.maxScrollExtent) break;
          scroll.position.jumpTo(
            (scroll.position.pixels + 250).clamp(
              0,
              scroll.position.maxScrollExtent,
            ),
          );
          await tester.pumpAndSettle();
        }
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        binding.reportData ??= <String, Object?>{};
        final shots = binding.reportData!.putIfAbsent(
          'screenshots',
          () => <Object?>[],
        ) as List<Object?>;
        shots.add({
          'screenshotName': 'catalogue-${brightness.name}-$scale',
          'bytes': data!.buffer.asUint8List().toList(),
        });
      });
    }
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:sctv_dl_mobile/design/ios_primary_navigation.dart';

const _contentHeight = 1200.0;

const _contrastPhases = [
  (name: 'initial-light', color: Colors.white, hasDarkContent: false),
  (name: 'scrolled-dark', color: Colors.black, hasDarkContent: true),
  (name: 'scrolled-light', color: Colors.white, hasDarkContent: false),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigation adapts to content independently of app brightness', (
    tester,
  ) async {
    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
    final capture = GlobalKey();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var selected = 0;
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          builder: (context, child) => LiquidGlassWidgets.wrap(
            brightnessResolver: Theme.maybeBrightnessOf,
            child: child!,
          ),
          home: GlassContentAwareScope(
            child: Scaffold(
              extendBody: true,
              body: GlassContentAwareContent(
                child: ListView(
                  controller: scroll,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final phase in _contrastPhases)
                      SizedBox(
                        height: _contentHeight,
                        child: ColoredBox(color: phase.color),
                      ),
                  ],
                ),
              ),
              bottomNavigationBar: IosPrimaryNavigation(
                selectedIndex: 0,
                activeDownloads: 2,
                onSelected: (index) => selected = index,
              ),
            ),
          ),
        ),
      ),
    );

    // Native readback is necessary: widget tests cannot verify the pixels
    // sampled behind the bar or the shader's resulting material.
    for (final (index, phase) in _contrastPhases.indexed) {
      scroll.jumpTo(index * _contentHeight);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        final luminance = tester
            .widget<GlassTabBar>(find.byType(GlassTabBar))
            .unselectedIconColor!
            .computeLuminance();
        final hasExpectedLuminance = phase.hasDarkContent
            ? luminance > 0.8
            : luminance < 0.1;
        if (hasExpectedLuminance) {
          break;
        }
      }
      final bar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(
        bar.unselectedIconColor!.computeLuminance(),
        phase.hasDarkContent ? greaterThan(0.8) : lessThan(0.1),
      );
      expect(
        bar.settings!.glassColor.computeLuminance(),
        phase.hasDarkContent ? lessThan(0.1) : greaterThan(0.8),
      );

      final surface =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await surface.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      binding.reportData ??= <String, Object?>{};
      final screenshots = binding.reportData!.putIfAbsent(
        'screenshots',
        () => <Object?>[],
      ) as List<Object?>;
      screenshots.add({
        'screenshotName': 'ios-glass-contrast-${phase.name}',
        'bytes': bytes!.buffer.asUint8List().toList(),
      });
      image.dispose();
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.text('下载').hitTestable().last);
    expect(selected, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isIOS);
}

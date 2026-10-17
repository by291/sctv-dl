import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/settings/preferences.dart';
import 'package:sctv_dl_mobile/features/settings/settings_page.dart';

import '../programmes/pages_test.dart' show host;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'large text settings preserve row actions and scrollable choices in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Preferences? changed;
        var clearCount = 0;
        await tester.pumpWidget(
          host(
            SettingsPage(
              preferences: const Preferences(),
              supportsDynamicColour: true,
              onChanged: (value) async => changed = value,
              onClearCache: () async {},
              onClearHistory: () async => clearCount++,
              version: '0.1.0 (1234)',
            ),
            scale: 2,
            brightness: brightness,
          ),
        );
        await tester.tap(find.text('主题'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('深色'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('深色'));
        await tester.pumpAndSettle();
        expect(changed?.theme, AppThemeMode.dark);
        await tester.scrollUntilVisible(find.text('仅 Wi-Fi 下载'), 200);
        await tester.ensureVisible(find.text('仅 Wi-Fi 下载'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('仅 Wi-Fi 下载'));
        await tester.pumpAndSettle();
        expect(changed?.wifiOnly, true);
        await tester.scrollUntilVisible(find.text('清空观看记录'), 200);
        await tester.tap(find.text('清空观看记录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(clearCount, 0);
        await tester.tap(find.text('清空观看记录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认'));
        await tester.pumpAndSettle();
        expect(clearCount, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('settings sheet blocks navigation beneath the modal', (
    tester,
  ) async {
    var navigated = false;
    await tester.pumpWidget(
      host(
        Scaffold(
          bottomNavigationBar: TextButton(
            onPressed: () => navigated = true,
            child: const Text('Navigation target'),
          ),
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => SettingsPage(
                preferences: const Preferences(),
                onChanged: (_) async {},
                onClearCache: () async {},
                onClearHistory: () async {},
                version: 'test',
              ),
            ),
          ),
        ),
      ),
    );
    final navigationPosition = tester.getCenter(find.text('Navigation target'));
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    await tester.tapAt(navigationPosition);
    await tester.pumpAndSettle();
    expect(navigated, false);
  });

  testWidgets('theme options support keyboard selection', (tester) async {
    Preferences? changed;
    await tester.pumpWidget(
      host(
        SettingsPage(
          preferences: const Preferences(),
          onChanged: (value) async => changed = value,
          onClearCache: () async {},
          onClearHistory: () async {},
          version: 'test',
        ),
      ),
    );
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    for (var index = 0; index < 8; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final tile = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ListTile>();
      if (tile?.title is Text && (tile!.title! as Text).data == '深色') break;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changed?.theme, AppThemeMode.dark);
  });
}

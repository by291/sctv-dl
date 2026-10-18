import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/app/providers.dart';
import 'package:sctv_dl_mobile/app/services.dart';
import 'package:sctv_dl_mobile/domain/settings/preferences.dart';
import 'package:sctv_dl_mobile/features/settings/settings_page.dart';

import '../support/fakes.dart';
import 'router_test.dart'
    show RouteDownloads, RouteHistory, CapturingBackend, UnusedCoverCache;

class FailingSettings extends FakeUserRepository {
  int saves = 0;
  final retry = Completer<void>();

  @override
  Future<void> savePreferences(Preferences value) async {
    if (saves++ == 0) throw StateError('disk unavailable');
    await retry.future;
    await super.savePreferences(value);
  }
}

void main() {
  testWidgets(
    'unsaved preferences remain usable and duplicate retry clicks save once',
    (tester) async {
      final user = FailingSettings();
      final services = AppServices(
        programmes: FakeProgrammeRepository(),
        user: user,
        history: RouteHistory(),
        downloads: RouteDownloads(),
        playback: CapturingBackend(),
        initialPreferences: const Preferences(),
        initialFavourites: {},
        version: 'test',
        coverCache: UnusedCoverCache(),
      );
      final container = ProviderContainer(
        overrides: [servicesProvider.overrideWithValue(services)],
      );
      addTearDown(container.dispose);
      addTearDown(user.close);
      addTearDown(services.dispose);
      final controller = container.read(preferencesProvider.notifier);

      await controller.save(const Preferences(theme: AppThemeMode.dark));
      expect(
        container.read(preferencesProvider).value.theme,
        AppThemeMode.dark,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(preferencesProvider);
                return SettingsPage(
                  preferences: state.value,
                  onChanged: controller.save,
                  onRetrySave: controller.retry,
                  persistenceError: state.error,
                  onClearCache: () async {},
                  onClearHistory: () async {},
                  version: 'test',
                );
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('设置暂未保存'), findsOneWidget);
      await tester.tap(find.text('重试保存'));
      await tester.tap(find.text('重试保存'));
      expect(user.saves, 2);
      user.retry.complete();
      await tester.pumpAndSettle();
      expect(user.preferences.theme, AppThemeMode.dark);
      expect(find.textContaining('设置暂未保存'), findsNothing);
    },
  );
}

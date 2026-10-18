import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/cover_image.dart';
import '../design/theme.dart';
import '../domain/settings/preferences.dart';
import 'providers.dart';
import 'router.dart';
import 'services.dart';

class SctvApp extends StatelessWidget {
  const SctvApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      servicesProvider.overrideWithValue(services),
      coverCacheProvider.overrideWithValue(services.coverCache),
    ],
    child: const _Application(),
  );
}

class _Application extends ConsumerStatefulWidget {
  const _Application();

  @override
  ConsumerState<_Application> createState() => _ApplicationState();
}

class _ApplicationState extends ConsumerState<_Application> {
  late final AppServices _services;
  late final router = createAppRouter(_services);
  StreamSubscription<String>? _notifications;

  @override
  void initState() {
    super.initState();

    _services = ref.read(servicesProvider);
    _notifications = _services.notificationTaps.listen((_) {
      if (mounted) router.go('/downloads');
    });
  }

  @override
  void dispose() {
    unawaited(_notifications?.cancel());
    router.dispose();

    unawaited(
      _services.dispose().catchError((Object error, StackTrace stack) {
        developer.log(
          'Application shutdown failed',
          error: error,
          stackTrace: stack,
        );
      }),
    );

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(preferencesProvider).value;

    return DynamicColorBuilder(
      builder: (light, dark) {
        final dynamic = Platform.isAndroid && preferences.dynamicColour;

        return MaterialApp.router(
          title: '蜀台回看',
          debugShowCheckedModeBanner: false,
          restorationScopeId: 'sctv-mobile',
          routerConfig: router,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN')],
          locale: const Locale('zh', 'CN'),
          theme: buildAppTheme(
            Brightness.light,
            dynamicScheme: dynamic && light != null
                ? ColorScheme.fromSeed(
                    seedColor: light.primary,
                    brightness: Brightness.light,
                  )
                : null,
          ),
          darkTheme: buildAppTheme(
            Brightness.dark,
            dynamicScheme: dynamic && dark != null
                ? ColorScheme.fromSeed(
                    seedColor: dark.primary,
                    brightness: Brightness.dark,
                  )
                : null,
          ),
          themeMode: switch (preferences.theme) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
        );
      },
    );
  }
}

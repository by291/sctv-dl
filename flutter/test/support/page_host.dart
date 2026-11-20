import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sctv_dl_mobile/design/theme.dart';

/// Configures the theme and text scaling for a hosted page.
class PageHostAppearance {
  const PageHostAppearance({
    this.textScale = 1,
    this.brightness = Brightness.light,
    this.theme,
  });

  final double textScale;
  final Brightness brightness;
  final ThemeData? theme;
}

/// Wraps a page in the application theme and a test provider scope.
Widget host(
  Widget child, {
  PageHostAppearance appearance = const PageHostAppearance(),
}) => ProviderScope(
  child: MaterialApp(
    theme: appearance.theme ?? buildAppTheme(appearance.brightness),
    restorationScopeId: 'test-app',
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(appearance.textScale)),
      child: widget!,
    ),
    home: child,
  ),
);

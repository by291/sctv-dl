import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'scroll_under_header.dart';
import 'viewport_hero.dart';

bool usesIosGlass(BuildContext context) =>
    !kIsWeb && Theme.of(context).platform == TargetPlatform.iOS;

/// Adapts primary browsing chrome while retaining Material notice ownership.
class PrimaryPageScaffold extends StatelessWidget {
  const PrimaryPageScaffold({
    super.key,
    required this.appBar,
    required this.bodyBuilder,
    this.scrollBehindToolbar = false,
    this.bottomNavigationBar,
  });

  final AppBar appBar;
  final Widget Function(BuildContext, EdgeInsets) bodyBuilder;
  final bool scrollBehindToolbar;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    if (!usesIosGlass(context)) {
      return Scaffold(
        appBar: appBar,
        body: bodyBuilder(context, EdgeInsets.zero),
        bottomNavigationBar: bottomNavigationBar,
      );
    }

    final theme = Theme.of(context);
    final toolbarHeight = appBar.toolbarHeight ?? kToolbarHeight;

    return Scaffold(
      extendBody: bottomNavigationBar != null,
      bottomNavigationBar: bottomNavigationBar,
      body: Builder(
        builder: (context) {
          final padding = MediaQuery.paddingOf(context);
          final contentInsets = scrollBehindToolbar
              ? EdgeInsets.only(
                  top: padding.top + toolbarHeight,
                  bottom: padding.bottom,
                )
              : EdgeInsets.zero;

          return GlassScaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            statusBarStyle: GlassStatusBarStyle.auto,
            extendBody: scrollBehindToolbar,
            topEdgeFade: false,
            // The outer Material scaffold owns keyboard resizing and SnackBars.
            resizeToAvoidBottomInset: false,
            appBar: GlassAppBar(
              toolbarHeight: toolbarHeight,
              centerTitle: false,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              title: DefaultTextStyle(
                style:
                    theme.appBarTheme.titleTextStyle ??
                    theme.textTheme.titleLarge!,
                child: appBar.title ?? const SizedBox.shrink(),
              ),
              leading:
                  appBar.leading ??
                  (appBar.automaticallyImplyLeading &&
                          ModalRoute.of(context)?.impliesAppBarDismissal == true
                      ? const BackButton()
                      : null),
              actions: appBar.actions ?? const [],
            ),
            body: ViewportHeroInsets(
              insets: contentInsets,
              child: scrollBehindToolbar
                  ? ScrollUnderHeader(
                      height: contentInsets.top,
                      color: theme.scaffoldBackgroundColor,
                      child: Builder(
                        builder: (context) =>
                            bodyBuilder(context, contentInsets),
                      ),
                    )
                  : Builder(
                      builder: (context) => bodyBuilder(context, contentInsets),
                    ),
            ),
          );
        },
      ),
    );
  }
}

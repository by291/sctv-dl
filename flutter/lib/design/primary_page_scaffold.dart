import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
    final padding = MediaQuery.paddingOf(context);
    final contentInsets = scrollBehindToolbar
        ? EdgeInsets.only(
            top: padding.top + toolbarHeight,
            bottom: padding.bottom,
          )
        : EdgeInsets.zero;

    return Scaffold(
      bottomNavigationBar: bottomNavigationBar,
      body: GlassScaffold(
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
                theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge!,
            child: appBar.title ?? const SizedBox.shrink(),
          ),
          leading: appBar.leading,
          actions: appBar.actions ?? const [],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Builder(builder: (context) => bodyBuilder(context, contentInsets)),
            if (scrollBehindToolbar)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: contentInsets.top,
                child: IgnorePointer(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: ColoredBox(
                        color: theme.scaffoldBackgroundColor.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

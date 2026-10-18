import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/shared_cover.dart';
import '../../../domain/programmes/programme.dart';

class ProgrammeCard extends StatelessWidget {
  const ProgrammeCard({
    super.key,
    required this.programme,
    required this.favourite,
    required this.onOpen,
    required this.onFavourite,
  });

  final Programme programme;
  final bool favourite;
  final VoidCallback onOpen;
  final VoidCallback onFavourite;

  static int titleMaxLines(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 2 : 1;

  static TextStyle _titleStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(height: 1.5);

  static double titleHeight(
    BuildContext context,
    Iterable<String> titles,
    double width,
  ) {
    final style = _titleStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final lines = titleMaxLines(context);
    var height = scaler.scale(style.fontSize!) * style.height! * lines;

    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: scaler,
      locale: Localizations.maybeLocaleOf(context),
      maxLines: lines,
      ellipsis: '…',
    );

    // CJK fallback fonts can exceed fontSize * height. Measure the same text
    // layout as the card, across the full catalogue so filtering keeps row sizes.
    for (final title in titles) {
      painter.text = TextSpan(text: title, style: style);
      painter.layout(maxWidth: width);
      height = math.max(height, painter.height);
    }

    painter.dispose();

    return height.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SharedCover(
                  tag: 'catalogue-${programme.id}',
                  url: programme.cover,
                  radius: 16,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: ClipOval(
                    child: IconButton.filledTonal(
                      tooltip: favourite
                          ? '取消收藏 ${programme.name}'
                          : '收藏 ${programme.name}',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        fixedSize: const Size(32, 32),
                        padding: const EdgeInsets.all(6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                        backgroundColor: colours.surface.withValues(alpha: .94),
                        foregroundColor: favourite
                            ? colours.primary
                            : colours.onSurfaceVariant,
                      ),
                      isSelected: favourite,
                      onPressed: onFavourite,
                      icon: const Icon(Icons.favorite_border, size: 20),
                      selectedIcon: const Icon(Icons.favorite, size: 20),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                programme.name,
                maxLines: titleMaxLines(context),
                overflow: TextOverflow.ellipsis,
                style: _titleStyle(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

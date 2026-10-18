import 'package:flutter/material.dart';

import '../../../design/content_transition.dart';
import '../../../design/shared_cover.dart';
import '../../../domain/programmes/programme.dart';

class ProgrammeExploration extends StatelessWidget {
  const ProgrammeExploration({
    super.key,
    required this.programme,
    required this.onOpen,
    this.onShuffle,
  });

  final Programme programme;
  final VoidCallback onOpen;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    final typography = Theme.of(context).textTheme;
    final cardColour = Color.alphaBlend(
      colours.primaryContainer.withValues(alpha: .35),
      Theme.of(context).scaffoldBackgroundColor,
    );

    return Card(
      color: cardColour,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
            final wide = constraints.maxWidth >= 480;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ContentTransition(
                  background: cardColour,
                  milliseconds: 160,
                  child: Row(
                    key: ValueKey(programme.id),
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '栏目探索',
                              style: typography.labelLarge?.copyWith(
                                color: colours.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height:
                                  MediaQuery.textScalerOf(context)
                                      .scale(typography.titleLarge!.fontSize!) *
                                  1.3 *
                                  (largeText ? 4 : 2),
                              child: Text(
                                programme.name,
                                maxLines: largeText ? 4 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: typography.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            if (wide) ...[
                              const SizedBox(height: 8),
                              Text(
                                '发现一个栏目，回看整期节目或精彩片段。',
                                style: typography.bodyMedium?.copyWith(
                                  color: colours.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!largeText) ...[
                        const SizedBox(width: 16),
                        SizedBox(
                          width: wide
                              ? 240
                              : (constraints.maxWidth * .46).clamp(112, 160),
                          child: SharedCover(
                            tag: 'exploration-${programme.id}',
                            url: programme.cover,
                            rotation: -.0872665,
                            frameInset: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colours.primaryContainer,
                        foregroundColor: colours.onPrimaryContainer,
                      ),
                      onPressed: onOpen,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('查看节目'),
                    ),
                    TextButton.icon(
                      onPressed: onShuffle,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('换一个'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

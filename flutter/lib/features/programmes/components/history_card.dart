import 'package:flutter/material.dart';

import '../../../design/cover_image.dart';
import '../../../domain/playback/history_repository.dart';

class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onRemove,
  });

  final ViewingEntry entry;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = entry.selection;
    final duration = entry.duration;
    final progress = duration == null || duration.inMilliseconds <= 0
        ? null
        : (entry.position.inMilliseconds / duration.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final position = _time(entry.position);
    final status = entry.completed
        ? '已看完 · 再看一次'
        : '继续观看 · $position${progress == null ? '' : ' / ${_time(duration!)}'}';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selection.programme.name,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '移除观看记录',
                        onPressed: onRemove,
                        color: theme.colorScheme.onSurfaceVariant,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!largeText) ...[
                        SizedBox(
                          width: 104,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CoverImage(
                              url:
                                  selection.content.cover ??
                                  selection.programme.cover,
                              aspectRatio: 4 / 3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selection.content.title,
                              maxLines: largeText ? null : 3,
                              overflow: largeText
                                  ? null
                                  : TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              selection.broadcast.date,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        entry.completed
                            ? Icons.replay_rounded
                            : Icons.play_circle_outline_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: entry.completed ? 1 : progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(3),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      semanticsLabel: '观看进度',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _time(Duration duration) {
  final seconds = duration.isNegative ? 0 : duration.inSeconds;
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

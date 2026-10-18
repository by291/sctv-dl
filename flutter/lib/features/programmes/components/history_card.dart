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
    final started = entry.position > Duration.zero;
    final knownDuration = duration != null && duration > Duration.zero;
    final progress = !entry.completed && started && knownDuration
        ? (entry.position.inMicroseconds / duration.inMicroseconds).clamp(
            0.0,
            1.0,
          )
        : null;

    final status = entry.completed
        ? '已看完'
        : !started
        ? '尚未播放'
        : '看到 ${_time(entry.position)}${knownDuration ? ' / ${_time(duration)}' : ''}';
    final action = entry.completed
        ? '再看一次'
        : started
        ? '继续观看'
        : '播放';

    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = largeText && constraints.maxWidth < 480;

              final cover = SizedBox(
                width: constraints.maxWidth < 340 ? 88 : 104,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      CoverImage(
                        url:
                            selection.content.cover ??
                            selection.programme.cover,
                      ),
                      if (progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            color: theme.colorScheme.primary,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            semanticsLabel: '观看进度',
                          ),
                        ),
                    ],
                  ),
                ),
              );

              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selection.content.title,
                    maxLines: largeText ? null : 2,
                    overflow: largeText ? null : TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${selection.programme.name} · ${selection.broadcast.date}',
                    style: muted,
                  ),
                ],
              );

              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: Icon(
                      entry.completed
                          ? Icons.replay_rounded
                          : Icons.play_arrow_rounded,
                      size: 20,
                    ),
                    label: Text(action),
                  ),
                  PopupMenuButton<_HistoryAction>(
                    tooltip: '更多操作',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (_) => onRemove?.call(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _HistoryAction.remove,
                        enabled: onRemove != null,
                        child: const Text('移除观看记录'),
                      ),
                    ],
                  ),
                ],
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                      child: stacked
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                cover,
                                const SizedBox(height: 10),
                                details,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                cover,
                                const SizedBox(width: 12),
                                Expanded(child: details),
                              ],
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 6),
                    child: stacked || constraints.maxWidth < 300
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(status, style: muted),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: actions,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: Text(status, style: muted)),
                              const SizedBox(width: 4),
                              actions,
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _HistoryAction { remove }

String _time(Duration duration) {
  final seconds = duration.isNegative ? 0 : duration.inSeconds;
  final minutes = seconds ~/ 60;
  final remainder = (seconds % 60).toString().padLeft(2, '0');

  if (minutes < 60) return '$minutes:$remainder';
  return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:$remainder';
}

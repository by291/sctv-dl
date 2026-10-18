import 'package:flutter/material.dart';

import '../../../design/shared_cover.dart';
import '../../../design/viewport_hero.dart';
import '../../../domain/programmes/programme.dart';
import '../../../domain/programmes/programme_policy.dart';

class ArchiveContentCard extends StatelessWidget {
  const ArchiveContentCard({
    super.key,
    required this.item,
    required this.programme,
    required this.broadcast,
    required this.fullEpisode,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
  });

  final ProgrammeContent item;
  final Programme programme;
  final BroadcastDate broadcast;
  final bool fullEpisode;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final playable = videoSources(item).isNotEmpty;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fullEpisode)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '完整节目',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        Text(
          item.title,
          maxLines: largeText ? 6 : 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (!fullEpisode)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              publicationLabel(item.publishedAt, broadcast.date),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (!playable)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('暂未提供视频'),
          ),
      ],
    );

    final content = fullEpisode || largeText
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _playArtwork(
                context,
                item,
                playable,
                fullEpisode: true,
                selected: selected,
              ),
              Padding(padding: const EdgeInsets.all(16), child: details),
            ],
          )
        : Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 104,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _playArtwork(
                      context,
                      item,
                      playable,
                      selected: selected,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: details),
              ],
            ),
          );

    return Semantics(
      checked: selectionMode ? selected : null,
      enabled: playable,
      label: selectionMode ? item.title : null,
      child: Card(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        child: InkWell(onTap: playable ? onTap : null, child: content),
      ),
    );
  }

  Widget _playArtwork(
    BuildContext context,
    ProgrammeContent item,
    bool playable, {
    bool fullEpisode = false,
    required bool selected,
  }) => Stack(
    children: [
      ViewportHero(
        child: SharedCover(
          tag: selectionMode
              ? null
              : 'playback-${programme.id}/${broadcast.id}/${item.id}',
          url: item.cover ?? programme.cover,
          radius: fullEpisode ? 12 : 10,
          aspectRatio: fullEpisode ? 16 / 9 : 4 / 3,
        ),
      ),
      if (playable || selectionMode)
        Positioned(
          right: fullEpisode ? 12 : 6,
          bottom: fullEpisode ? 12 : 6,
          child: Container(
            width: fullEpisode ? 40 : 28,
            height: fullEpisode ? 40 : 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .94),
            ),
            child: Icon(
              selectionMode
                  ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                  : Icons.play_arrow_rounded,
              color: playable
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).disabledColor,
              size: fullEpisode ? 24 : 18,
            ),
          ),
        ),
    ],
  );
}

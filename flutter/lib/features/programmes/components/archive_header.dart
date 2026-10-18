import 'package:flutter/material.dart';

import '../../../design/shared_cover.dart';
import '../../../domain/programmes/programme.dart';

class ArchiveHeader extends StatelessWidget {
  const ArchiveHeader({
    super.key,
    required this.programme,
    required this.favourite,
    required this.onFavourite,
    required this.scroll,
    this.coverTag,
  });

  final Programme programme;
  final bool favourite;
  final VoidCallback onFavourite;
  final ScrollController scroll;
  final String? coverTag;

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          programme.name,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
          onPressed: onFavourite,
          icon: Icon(
            favourite ? Icons.favorite : Icons.favorite_border,
            size: 18,
          ),
          label: Text(favourite ? '已收藏' : '收藏栏目'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) return details;

        final cover = ListenableBuilder(
          listenable: scroll,
          builder: (context, _) => SharedCover(
            // A clipped/offscreen cover must not reappear above the app bar
            // when returning from a scrolled archive.
            tag: !scroll.hasClients || scroll.offset <= 8 ? coverTag : null,
            url: programme.cover,
          ),
        );

        final compact = constraints.maxWidth < 348;
        final gap = compact ? 12.0 : 16.0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: ((constraints.maxWidth - gap) * (compact ? .52 : .54))
                  .clamp(0, 256),
              child: cover,
            ),
            SizedBox(width: gap),
            Expanded(child: details),
          ],
        );
      },
    );
  }
}

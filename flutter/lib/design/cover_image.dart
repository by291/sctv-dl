import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final coverCacheProvider = Provider<BaseCacheManager?>((ref) => null);

class CoverImage extends ConsumerWidget {
  const CoverImage({super.key, this.url, this.aspectRatio = 16 / 9});
  final String? url;
  final double aspectRatio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colours = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colours.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.live_tv_rounded,
          color: colours.onSurfaceVariant.withValues(alpha: .45),
          size: 36,
        ),
      ),
    );
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: url == null || url!.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url!,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                cacheManager: ref.watch(coverCacheProvider),
                fit: BoxFit.cover,
                memCacheWidth: 900,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

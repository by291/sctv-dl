import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../domain/downloads/download_repository.dart';
import '../domain/playback/history_repository.dart';
import '../domain/playback/playback_backend.dart';
import '../domain/programmes/programme_repository.dart';
import '../domain/settings/preferences.dart';
import '../domain/settings/user_repository.dart';
import '../features/programmes/library_controller.dart';
import 'resource_cleanup.dart';

class AppServices {
  AppServices({
    required this.programmes,
    required this.user,
    required this.history,
    required this.downloads,
    required this.playback,
    required this.initialPreferences,
    required this.initialFavourites,
    required this.version,
    required this.coverCache,
    this.notificationTaps = const Stream.empty(),
    this.closeResources,
  });

  final ProgrammeRepository programmes;
  final UserRepository user;
  final HistoryRepository history;
  final DownloadRepository downloads;
  final PlaybackBackend playback;

  final Preferences initialPreferences;
  final Set<String> initialFavourites;
  final String version;

  final BaseCacheManager coverCache;
  final Stream<String> notificationTaps;
  final Future<void> Function()? closeResources;

  Future<void>? _disposal;

  late final library = LibraryController(
    repository: programmes,
    user: user,
    initialFavourites: initialFavourites,
  );

  Future<void> clearCache() async {
    await programmes.clearCache();
    await coverCache.emptyCache();
  }

  Future<void> dispose() => _disposal ??= closeAppResources([
    library.dispose,
    downloads.dispose,
    coverCache.dispose,
    ?closeResources,
  ]);
}

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database/record_database.dart';
import '../data/downloads/durable_download_repository.dart';
import '../data/downloads/sqlite_download_task_store.dart';
import '../data/playback/drift_history_repository.dart';
import '../data/programmes/cached_programme_repository.dart';
import '../data/programmes/dio_programme_client.dart';
import '../data/settings/drift_user_repository.dart';
import '../data/settings/installation_identity.dart';
import '../domain/downloads/download_repository.dart';
import '../domain/playback/history_repository.dart';
import '../domain/playback/playback_backend.dart';
import '../domain/programmes/programme.dart';
import '../domain/programmes/programme_repository.dart';
import '../domain/settings/preferences.dart';
import '../domain/settings/user_repository.dart';
import '../features/programmes/library_controller.dart';
import '../platform/downloads/background_transfer_gateway.dart';
import '../platform/files/native_download_files.dart';
import '../platform/images/strict_cover_client.dart';
import '../platform/playback/better_player_backend.dart';
import '../platform/storage/runtime_backup_policy.dart';

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
  late final library = LibraryController(
    repository: programmes,
    user: user,
    initialFavourites: initialFavourites,
  );

  Future<void> clearCache() async {
    await programmes.clearCache();
    await coverCache.emptyCache();
  }

  Future<void> dispose() async {
    library.dispose();
    await downloads.dispose();
    await coverCache.dispose();
    await closeResources?.call();
  }
}

Future<AppServices> bootstrapServices() async {
  final package = await PackageInfo.fromPlatform();
  final support = await getApplicationSupportDirectory();
  final runtimeDirectory = Directory('${support.path}/runtime');
  await runtimeDirectory.create(recursive: true);
  if (Platform.isIOS) {
    await excludeIOSRuntimeState(
      support: support,
      documents: await getApplicationDocumentsDirectory(),
    );
  }
  // These instances use independent executors and different files so that only
  // preferences, favourites and history participate in user backup.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final userDatabase = RecordDatabase.open(File('${support.path}/user.sqlite'));
  final runtimeDatabase = RecordDatabase.open(
    File('${runtimeDirectory.path}/runtime.sqlite'),
  );
  DioProgrammeClient? client;
  BackgroundTransferGateway? transfers;
  BaseCacheManager? covers;
  try {
    final profile = Platform.isAndroid
        ? await _androidProfile()
        : const MetadataDeviceProfile.iosCompatibility();
    client = DioProgrammeClient(
      identity: InstallationIdentity(runtimeDatabase, profile: profile),
    );
    final programmes = CachedProgrammeRepository(
      database: runtimeDatabase,
      client: client,
    );
    final user = DriftUserRepository(userDatabase);
    final history = DriftHistoryRepository(userDatabase);
    final preferences = await user.loadPreferences();
    final favourites = await user.loadFavourites();
    final transferGateway = BackgroundTransferGateway(
      appVersion: package.version,
    );
    transfers = transferGateway;
    final downloads = DurableDownloadRepository(
      store: SqliteDownloadTaskStore(runtimeDatabase),
      transfers: transferGateway,
      files: NativeDownloadFiles(),
      revalidate: (old) async {
        final dates = await programmes.refreshDates(old.programme.id);
        final broadcast = dates.items
            .where((date) => date.id == old.broadcast.id)
            .firstOrNull;
        if (broadcast == null) throw StateError('原播出日期已不可用');
        final contents = await programmes.refreshContents(
          old.programme.id,
          broadcast.id,
        );
        final content = contents.items
            .where((item) => item.id == old.content.id)
            .firstOrNull;
        if (content == null) throw StateError('原节目内容已不可用');
        return ProgrammeSelection(
          programme: old.programme,
          broadcast: broadcast,
          content: content,
        );
      },
    );
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    covers = CacheManager(
      Config(
        'sctv-covers-v1',
        stalePeriod: const Duration(days: 30),
        maxNrOfCacheObjects: 300,
        fileService: HttpFileService(
          httpClient: StrictCoverClient(client: IOClient(http)),
        ),
      ),
    );
    final ownedClient = client;
    return AppServices(
      programmes: programmes,
      user: user,
      history: history,
      downloads: downloads,
      playback: BetterPlayerBackend(userAgent: 'sctv-dl/${package.version}'),
      initialPreferences: preferences,
      initialFavourites: favourites,
      version: '${package.version} (${package.buildNumber})',
      coverCache: covers,
      notificationTaps: transferGateway.notificationTaps,
      closeResources: () async {
        await transferGateway.dispose();
        ownedClient.close();
        await userDatabase.close();
        await runtimeDatabase.close();
      },
    );
  } catch (_) {
    client?.close();
    await transfers?.dispose();
    await covers?.dispose();
    await userDatabase.close();
    await runtimeDatabase.close();
    rethrow;
  }
}

Future<MetadataDeviceProfile> _androidProfile() async {
  final device = await DeviceInfoPlugin().androidInfo;
  return MetadataDeviceProfile.android(
    brand: device.brand,
    model: device.model,
    systemVersion: device.version.release,
  );
}

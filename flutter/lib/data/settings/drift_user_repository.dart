import '../../domain/programmes/programme.dart';
import '../../domain/settings/preferences.dart';
import '../../domain/settings/user_repository.dart';
import '../database/record_database.dart';

class DriftUserRepository implements UserRepository {
  DriftUserRepository(this._database);

  final RecordDatabase _database;

  Future<void> _writeTail = Future<void>.value();
  Future<void>? _migration;

  Future<void> _serialize(Future<void> Function() action) {
    final result = _writeTail.then((_) => action());

    // A failed save is reported to its caller without blocking later changes.
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );

    return result;
  }

  Future<void> _migrate() => _migration ??= _database
      .transaction(() async {
        final current = await _database.read('preferences', 'current');
        if (current != null) return;

        final legacy = await _database.read('settings', 'preferences');
        if (legacy == null) return;

        await _database.write(
          'preferences',
          'current',
          _encodePreferences(_decodePreferences(legacy)),
        );

        final favourites = legacy['favourites'];
        if (favourites is List) {
          for (final id
              in favourites.whereType<String>().where(_isId).toSet()) {
            await _database.write('favourites', id, {'id': id});
          }
        }

        await _database.remove('settings', 'preferences');
      })
      .onError((Object error, StackTrace stack) {
        _migration = null;
        Error.throwWithStackTrace(error, stack);
      });

  @override
  Future<Preferences> loadPreferences() async {
    await _migrate();

    return _decodePreferences(
      await _database.read('preferences', 'current') ?? {},
    );
  }

  @override
  Future<void> savePreferences(Preferences preferences) => _serialize(() async {
    await _migrate();

    await _database.write(
      'preferences',
      'current',
      _encodePreferences(preferences),
    );
  });

  @override
  Stream<Preferences> watchPreferences() async* {
    await _migrate();

    yield* _database
        .watch('preferences')
        .map((rows) => _decodePreferences(rows['current'] ?? {}));
  }

  @override
  Future<Set<String>> loadFavourites() async {
    await _migrate();

    return (await _database.all('favourites')).keys.where(_isId).toSet();
  }

  @override
  Future<void> toggleFavourite(String programmeId) => _serialize(() async {
    if (!_isId(programmeId)) {
      throw const FormatException('Invalid programme ID');
    }
    await _migrate();

    await _database.transaction(() async {
      final existing = await _database.read('favourites', programmeId);
      if (existing == null) {
        await _database.write('favourites', programmeId, {'id': programmeId});
      } else {
        await _database.remove('favourites', programmeId);
      }
    });
  });

  @override
  Stream<Set<String>> watchFavourites() async* {
    await _migrate();

    yield* _database
        .watch('favourites')
        .map((rows) => rows.keys.where(_isId).toSet());
  }
}

bool _isId(String value) => RegExp(r'^\d+$').hasMatch(value);

Preferences _decodePreferences(Map<String, Object?> value) => Preferences(
  theme:
      AppThemeMode.values
          .where((mode) => mode.name == value['theme'])
          .firstOrNull ??
      AppThemeMode.system,
  quality:
      VideoQuality.values
          .where((quality) => quality.name == value['quality'])
          .firstOrNull ??
      VideoQuality.standard,
  wifiOnly: value['wifiOnly'] is bool ? value['wifiOnly'] as bool : false,
  dynamicColour: value['dynamicColour'] is bool
      ? value['dynamicColour'] as bool
      : false,
);

Map<String, Object?> _encodePreferences(Preferences value) => {
  'version': 1,
  'theme': value.theme.name,
  'quality': value.quality.name,
  'wifiOnly': value.wifiOnly,
  'dynamicColour': value.dynamicColour,
};

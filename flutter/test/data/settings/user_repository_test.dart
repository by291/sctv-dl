import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/data/database/record_database.dart';
import 'package:sctv_dl_mobile/data/settings/drift_user_repository.dart';
import 'package:sctv_dl_mobile/data/settings/installation_identity.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/domain/settings/preferences.dart';

void main() {
  test(
    'failed preference migration preserves legacy data for a retry',
    () async {
      final database = FailingRecordDatabase();
      await database.write('settings', 'preferences', {
        'theme': 'dark',
        'quality': 'smooth',
        'favourites': ['4'],
      });
      database.failCollection = 'preferences';
      final repository = DriftUserRepository(database);
      try {
        await expectLater(repository.loadPreferences(), throwsStateError);
        expect(
          (await repository.loadPreferences()).quality,
          VideoQuality.smooth,
        );
        expect((await repository.loadPreferences()).theme, AppThemeMode.dark);
        expect(await repository.loadFavourites(), {'4'});
      } finally {
        await database.close();
      }
    },
  );

  test('preferences validate each stored field independently and publish durable changes', () async {
    final database = RecordDatabase.memory();
    await database.write('preferences', 'current', {
      'version': 1,
      'theme': 'unknown',
      'quality': 'smooth',
      'wifiOnly': 'true',
      'dynamicColour': true,
    });
    final repository = DriftUserRepository(database);
    try {
      final loaded = await repository.loadPreferences();
      expect(loaded.theme, AppThemeMode.system);
      expect(loaded.quality, VideoQuality.smooth);
      expect(loaded.wifiOnly, isFalse);
      expect(loaded.dynamicColour, isTrue);
      final updated = repository.watchPreferences().firstWhere(
        (value) => value.theme == AppThemeMode.dark,
      );
      await repository.savePreferences(
        loaded.copyWith(theme: AppThemeMode.dark),
      );
      expect((await updated).quality, VideoQuality.smooth);
    } finally {
      await database.close();
    }
  });

  test(
    'a failed preference write is surfaced and later saves remain usable',
    () async {
      final database = FailingRecordDatabase();
      final repository = DriftUserRepository(database);
      try {
        await repository.savePreferences(
          const Preferences(theme: AppThemeMode.light),
        );
        database.failCollection = 'preferences';
        await expectLater(
          repository.savePreferences(
            const Preferences(theme: AppThemeMode.dark),
          ),
          throwsStateError,
        );
        expect((await repository.loadPreferences()).theme, AppThemeMode.light);
        await repository.savePreferences(
          const Preferences(theme: AppThemeMode.dark),
        );
        expect((await repository.loadPreferences()).theme, AppThemeMode.dark);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'identity initialization retries after a transient storage failure',
    () async {
      final database = FailingRecordDatabase()..failCollection = 'installation';
      final identity = InstallationIdentity(
        database,
        profile: const MetadataDeviceProfile.iosCompatibility(),
      );
      try {
        await expectLater(identity.headers(), throwsStateError);
        expect(
          (await identity.headers())['deviceId'],
          matches(RegExp(r'^[a-f0-9-]{36}$')),
        );
      } finally {
        await database.close();
      }
    },
  );

  test(
    'legacy preferences migrate valid fields and shared favourite IDs',
    () async {
      final database = RecordDatabase.memory();
      final fixture =
          (jsonDecode(
                await File('../shared/fixtures/settings.json').readAsString(),
              ) as List).single
              as Map;
      await database.write(
        'settings',
        'preferences',
        Map<String, Object?>.from(fixture['raw'] as Map),
      );
      final repository = DriftUserRepository(database);

      try {
        final preferences = await repository.loadPreferences();
        expect(preferences.theme, AppThemeMode.system);
        expect(preferences.quality, VideoQuality.standard);
        expect(await repository.loadFavourites(), {'1'});
        await repository.savePreferences(
          preferences.copyWith(theme: AppThemeMode.dark),
        );
        expect((await repository.loadPreferences()).theme, AppThemeMode.dark);
      } finally {
        await database.close();
      }
    },
  );

  test('concurrent preference saves preserve submission order and favourites are atomic', () async {
    final database = RecordDatabase.memory();
    final repository = DriftUserRepository(database);

    try {
      await Future.wait([
        repository.savePreferences(const Preferences(theme: AppThemeMode.dark)),
        repository.savePreferences(
          const Preferences(theme: AppThemeMode.light),
        ),
        repository.toggleFavourite('9'),
        repository.toggleFavourite('9'),
      ]);

      expect((await repository.loadPreferences()).theme, AppThemeMode.light);
      expect(await repository.loadFavourites(), isEmpty);
      final next = repository.watchFavourites().firstWhere(
        (ids) => ids.contains('7'),
      );
      await repository.toggleFavourite('7');
      expect(await next, {'7'});
      await expectLater(
        repository.toggleFavourite('../1'),
        throwsFormatException,
      );
    } finally {
      await database.close();
    }
  });

  test(
    'concurrent identity requests create one persisted guest UUID',
    () async {
      final database = RecordDatabase.memory();
      final identity = InstallationIdentity(
        database,
        profile: const MetadataDeviceProfile.iosCompatibility(),
      );

      try {
        final profiles = await Future.wait(
          List.generate(12, (_) => identity.headers()),
        );
        final first = profiles.first;
        expect(
          profiles.map((value) => value['deviceId']).toSet(),
          hasLength(1),
        );
        expect(first['deviceId'], matches(RegExp(r'^[a-f0-9-]{36}$')));
        expect(first['deviceBrand'], 'google');
        expect(first['deviceModel'], 'Pixel 8');
        expect(first['systemVersion'], '14');
        expect(first['deviceType'], 'android');
        expect(first['appVersion'], '9.6.1.5');
        expect(first['Authorization'], '');
        expect(first.containsKey('Referer'), isFalse);
        final reopened = InstallationIdentity(
          database,
          profile: const MetadataDeviceProfile.android(
            brand: 'test',
            model: 'native',
            systemVersion: '17',
          ),
        );
        expect((await reopened.headers())['deviceId'], first['deviceId']);
        expect((await reopened.headers())['deviceModel'], 'native');
      } finally {
        await database.close();
      }
    },
  );
}

class FailingRecordDatabase extends RecordDatabase {
  FailingRecordDatabase() : super.memory();

  String? failCollection;

  @override
  Future<void> write(
    String collection,
    String key,
    Map<String, Object?> value,
  ) async {
    if (collection == failCollection) {
      failCollection = null;
      throw StateError('Fixture storage failure');
    }
    await super.write(collection, key, value);
  }
}

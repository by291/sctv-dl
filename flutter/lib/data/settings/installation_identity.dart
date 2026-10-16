import 'package:uuid/uuid.dart';

import '../database/record_database.dart';

class MetadataDeviceProfile {
  const MetadataDeviceProfile.android({
    required this.brand,
    required this.model,
    required this.systemVersion,
  });

  const MetadataDeviceProfile.iosCompatibility()
    : brand = 'google',
      model = 'Pixel 8',
      systemVersion = '14';

  final String brand;
  final String model;
  final String systemVersion;
}

/// Installation identity belongs in the runtime database, outside user backup.
class InstallationIdentity {
  InstallationIdentity(this._database, {required this.profile});

  final RecordDatabase _database;
  final MetadataDeviceProfile profile;
  Future<String>? _deviceId;

  Future<String> _loadDeviceId() => _deviceId ??= _database
      .transaction(() async {
        final stored = await _database.read(
          'installation',
          'metadata_identity',
        );
        final previous = stored?['id'];
        final id = previous is String && Uuid.isValidUUID(fromString: previous)
            ? previous
            : const Uuid().v4();

        await _database.write('installation', 'metadata_identity', {
          'id': id,
          'brand': profile.brand,
          'model': profile.model,
          'systemVersion': profile.systemVersion,
        });
        return id;
      })
      .onError((Object error, StackTrace stack) {
        _deviceId = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<Map<String, String>> headers() async => Map.unmodifiable({
    'userId': '',
    'Authorization': '',
    'captchaId': '',
    'deviceId': await _loadDeviceId(),
    'deviceBrand': profile.brand,
    'deviceModel': profile.model,
    'systemVersion': profile.systemVersion,
    'deviceType': 'android',
    'appVersion': '9.6.1.5',
    'User-Agent': 'okhttp/4.12.0',
    'Accept': 'application/json',
  });
}

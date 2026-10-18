import 'preferences.dart';

abstract interface class UserRepository {
  Future<Preferences> loadPreferences();
  Future<void> savePreferences(Preferences preferences);
  Stream<Preferences> watchPreferences();

  Future<Set<String>> loadFavourites();
  Future<void> toggleFavourite(String programmeId);
  Stream<Set<String>> watchFavourites();
}

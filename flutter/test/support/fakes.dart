import 'dart:async';

import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme_repository.dart';
import 'package:sctv_dl_mobile/domain/settings/preferences.dart';
import 'package:sctv_dl_mobile/domain/settings/user_repository.dart';

ProgrammeSnapshot<T> snapshot<T>(List<T> items, String revision) =>
    ProgrammeSnapshot(
      items: items,
      revision: revision,
      fetchedAt: DateTime.utc(2026, 10, 16),
    );

class FakeProgrammeRepository implements ProgrammeRepository {
  ProgrammeSnapshot<Programme>? cachedCatalogue;
  ProgrammeSnapshot<Programme> catalogue = snapshot([], 'empty');
  ProgrammeSnapshot<BroadcastDate>? savedDates;
  ProgrammeSnapshot<BroadcastDate> dates = snapshot([], 'empty');
  final Map<String, ProgrammeSnapshot<ProgrammeContent>> contents = {};
  final Map<String, Future<ProgrammeSnapshot<ProgrammeContent>>>
  delayedContents = {};

  @override
  Future<ProgrammeSnapshot<Programme>?> cachedProgrammes() async =>
      cachedCatalogue;
  @override
  Future<ProgrammeSnapshot<Programme>> refreshProgrammes({
    RequestScope? scope,
  }) async => catalogue;
  @override
  Future<ProgrammeSnapshot<BroadcastDate>?> cachedDates(
    String programmeId,
  ) async => savedDates;
  @override
  Future<ProgrammeSnapshot<BroadcastDate>> refreshDates(
    String programmeId, {
    RequestScope? scope,
  }) async => dates;
  @override
  Future<ProgrammeSnapshot<ProgrammeContent>?> cachedContents(
    String programmeId,
    String dateId,
  ) async => contents[dateId];
  @override
  Future<ProgrammeSnapshot<ProgrammeContent>> refreshContents(
    String programmeId,
    String dateId, {
    RequestScope? scope,
  }) async =>
      await (delayedContents[dateId] ??
          Future.value(contents[dateId] ?? snapshot([], 'empty')));
  @override
  Future<void> clearCache() async {
    cachedCatalogue = null;
    contents.clear();
  }
}

class FakeUserRepository implements UserRepository {
  Preferences preferences = const Preferences();
  Set<String> favourites = {};
  final _preferences = StreamController<Preferences>.broadcast();
  final _favourites = StreamController<Set<String>>.broadcast();

  @override
  Future<Preferences> loadPreferences() async => preferences;
  @override
  Future<void> savePreferences(Preferences value) async {
    preferences = value;
    _preferences.add(value);
  }

  @override
  Stream<Preferences> watchPreferences() => _preferences.stream;
  @override
  Future<Set<String>> loadFavourites() async => {...favourites};
  @override
  Stream<Set<String>> watchFavourites() => _favourites.stream;
  @override
  Future<void> toggleFavourite(String id) async {
    favourites = {...favourites};
    favourites.contains(id) ? favourites.remove(id) : favourites.add(id);
    _favourites.add({...favourites});
  }

  Future<void> close() async {
    await _preferences.close();
    await _favourites.close();
  }
}

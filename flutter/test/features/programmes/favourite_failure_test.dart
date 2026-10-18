import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/features/programmes/favourite_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/library_controller.dart';

import '../../support/fakes.dart';

void main() {
  test(
    'retry preserves newer observation failures and shares duplicate requests',
    () async {
      final user = ObservationFailure();
      final controller = FavouriteController(user, {});
      addTearDown(controller.dispose);
      addTearDown(user.close);
      controller.observe();
      await Future<void>.delayed(Duration.zero);
      expect(controller.error, isNotNull);

      final first = controller.retry();
      final second = controller.retry();
      await Future<void>.delayed(Duration.zero);
      user.reading.complete({'1'});
      await Future.wait([first, second]);

      expect(controller.error, contains('watch unavailable'));
      expect(controller.values, {'1'});
      expect(user.observations, 2);
      await controller.retry();
      expect(user.observations, 3);
    },
  );

  test('a stale retry snapshot cannot replace a new stream value followed by an error', () async {
    final user = ObservationFailure();
    final changes = StreamController<Set<String>>();
    user.replacement = changes.stream;
    final controller = FavouriteController(user, {});
    addTearDown(controller.dispose);
    addTearDown(user.close);
    addTearDown(changes.close);
    controller.observe();
    await Future<void>.delayed(Duration.zero);

    final retry = controller.retry();
    await Future<void>.delayed(Duration.zero);
    changes.add({'2'});
    changes.addError(StateError('new stream failed'));
    await Future<void>.delayed(Duration.zero);
    user.reading.complete({'1'});
    await retry;

    expect(controller.values, {'2'});
    expect(controller.error, contains('new stream failed'));
  });

  test('two failed favourite edits retain the confirmed empty set', () async {
    final user = FailingFavourites();
    final controller = LibraryController(
      repository: FakeProgrammeRepository(),
      user: user,
      initialFavourites: {},
    );
    addTearDown(controller.dispose);
    addTearDown(user.close);

    final first = controller.toggleFavourite('1');
    final second = controller.toggleFavourite('2');
    await Future<void>.delayed(Duration.zero);
    user.writes.first.completeError(StateError('first write failed'));
    await first;
    await Future<void>.delayed(Duration.zero);
    user.writes.last.completeError(StateError('second write failed'));
    await second;

    expect(controller.favourites, isEmpty);
  });
  test('programme refresh cannot erase a failed favourite save', () async {
    final user = FailingFavourites();
    final controller = LibraryController(
      repository: FakeProgrammeRepository(),
      user: user,
      initialFavourites: {},
    );
    addTearDown(controller.dispose);
    addTearDown(user.close);

    final saving = controller.toggleFavourite('1');
    await Future<void>.delayed(Duration.zero);
    user.writes.single.completeError(StateError('disk unavailable'));
    await saving;
    await controller.refresh();

    expect(controller.favouriteError, contains('disk unavailable'));
    expect(controller.error, isNull);
  });

  test(
    'retry after an acknowledged-write read failure never toggles it off',
    () async {
      final user = CommitThenFailRead();
      final controller = LibraryController(
        repository: FakeProgrammeRepository(),
        user: user,
        initialFavourites: {},
      );
      addTearDown(controller.dispose);
      addTearDown(user.close);

      await controller.toggleFavourite('1');
      expect(controller.favouriteError, isNotNull);
      await Future.wait([
        controller.retryFavourites(),
        controller.retryFavourites(),
      ]);

      expect(user.favourites, {'1'});
      expect(controller.favourites, {'1'});
      expect(controller.favouriteError, isNull);
      expect(user.toggles, 1);
    },
  );

  test('a completed failed observation can restart without losing confirmed values', () async {
    final user = FailedObservation();
    final controller = LibraryController(
      repository: FakeProgrammeRepository(),
      user: user,
      initialFavourites: {'1'},
    );
    addTearDown(controller.dispose);
    addTearDown(user.close);

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.favourites, {'1'});
    expect(controller.favouriteError, isNotNull);
    await controller.retryFavourites();
    await Future<void>.delayed(Duration.zero);

    expect(controller.favourites, {'2'});
    expect(controller.favouriteError, isNull);
  });
}

class FailingFavourites extends FakeUserRepository {
  final writes = <Completer<void>>[];

  @override
  Future<void> toggleFavourite(String id) {
    final pending = Completer<void>();
    writes.add(pending);
    return pending.future;
  }
}

class CommitThenFailRead extends FakeUserRepository {
  bool failNextRead = false;
  int toggles = 0;

  @override
  Future<void> toggleFavourite(String id) async {
    toggles++;
    await super.toggleFavourite(id);
    failNextRead = true;
  }

  @override
  Future<Set<String>> loadFavourites() async {
    if (failNextRead) {
      failNextRead = false;
      throw StateError('read failed after commit');
    }
    return super.loadFavourites();
  }
}

class FailedObservation extends FakeUserRepository {
  int observations = 0;

  @override
  Stream<Set<String>> watchFavourites() async* {
    if (observations++ == 0) throw StateError('observer failed');
    yield {'2'};
  }

  @override
  Future<Set<String>> loadFavourites() async => {'2'};
}

class ObservationFailure extends FakeUserRepository {
  final reading = Completer<Set<String>>();
  int observations = 0;
  Stream<Set<String>>? replacement;

  @override
  Stream<Set<String>> watchFavourites() {
    observations++;
    if (observations > 1 && replacement != null) return replacement!;
    return Stream.error(StateError('watch unavailable'));
  }

  @override
  Future<Set<String>> loadFavourites() => reading.future;
}

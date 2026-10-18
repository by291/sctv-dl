import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme_repository.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_controller.dart';
import 'package:sctv_dl_mobile/features/programmes/library_controller.dart';

import '../../support/fakes.dart';

void main() {
  const programme = Programme(id: '1', name: 'News');
  const first = BroadcastDate(id: '11', date: '2026-10-16');
  const second = BroadcastDate(id: '12', date: '2026-10-15');

  test(
    'catalogue updates remain pending until accepted, including empty data',
    () async {
      final repository = FakeProgrammeRepository()
        ..cachedCatalogue = snapshot([programme], 'old')
        ..catalogue = snapshot([], 'new');
      final user = FakeUserRepository();
      final controller = LibraryController(
        repository: repository,
        user: user,
        initialFavourites: {},
      );
      addTearDown(controller.dispose);
      addTearDown(user.close);
      await controller.initialize();
      expect(controller.programmes.map((item) => item.id), ['1']);
      expect(controller.hasPendingUpdate, isTrue);
      controller.acceptUpdate();
      expect(controller.programmes, isEmpty);
      expect(controller.hasPendingUpdate, isFalse);
    },
  );

  test(
    'favourite filtering preserves catalogue ordering and the current query',
    () async {
      final repository = FakeProgrammeRepository()
        ..catalogue = snapshot([
          programme,
          const Programme(id: '2', name: 'Music'),
        ], 'one');
      final user = FakeUserRepository()..favourites = {'2'};
      final controller = LibraryController(
        repository: repository,
        user: user,
        initialFavourites: {'2'},
      );
      addTearDown(controller.dispose);
      addTearDown(user.close);
      await controller.initialize();
      expect(controller.visibleProgrammes().map((item) => item.id), ['2', '1']);
      await controller.toggleFavourite('1');
      expect(controller.visibleProgrammes().map((item) => item.id), ['2', '1']);
      expect(
        controller
            .visibleProgrammes(favouritesOnly: true)
            .map((item) => item.id),
        ['2', '1'],
      );
      controller.setQuery('News');
      expect(controller.visibleProgrammes(), hasLength(1));
      expect(controller.visibleProgrammes(favouritesOnly: true), hasLength(1));
    },
  );

  test(
    'an old date response cannot replace a newer selected broadcast',
    () async {
      final delayed = Completer<ProgrammeSnapshot<ProgrammeContent>>();
      final repository = FakeProgrammeRepository()
        ..dates = snapshot([first, second], 'dates')
        ..delayedContents['11'] = delayed.future
        ..contents['12'] = snapshot([
          const ProgrammeContent(id: '22', title: 'Second'),
        ], 'second');
      final controller = ArchiveController(
        repository: repository,
        programme: programme,
      );
      addTearDown(controller.dispose);
      final opening = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      await controller.selectDate(second);
      delayed.complete(
        snapshot([const ProgrammeContent(id: '21', title: 'First')], 'first'),
      );
      await opening;
      expect(controller.selectedDate?.id, '12');
      expect(controller.contents.map((item) => item.id), ['22']);
    },
  );

  test('batch selection excludes missing media and blocks pending updates until exited', () async {
    final repository = FakeProgrammeRepository()
      ..dates = snapshot([first], 'dates')
      ..contents['11'] = snapshot([
        const ProgrammeContent(
          id: '1',
          title: 'News（2026.10.16）',
          video: 'https://fscgc.scgchc.com/a.mp4',
        ),
        const ProgrammeContent(id: '2', title: 'Unavailable'),
      ], 'old');
    final controller = ArchiveController(
      repository: repository,
      programme: programme,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.enterSelection();
    controller.selectAll();
    expect(controller.selectedIds, {'1'});
    repository.contents['11'] = snapshot([], 'new');
    await controller.refresh();
    controller.acceptUpdates();
    expect(controller.contents, hasLength(2));
    controller.exitSelection();
    controller.acceptUpdates();
    expect(controller.contents, isEmpty);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sctv_dl_mobile/app/app.dart';
import 'package:sctv_dl_mobile/app/bootstrap.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme_policy.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';
import 'package:sctv_dl_mobile/platform/playback/better_player_backend.dart';

/// Run on disposable Android/iOS runtimes while the host samples memory.
/// Android uses a 192 MiB app heap; iOS simulator results do not establish
/// physical-device jetsam limits. The journey checks playback and replacement.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('LIVE_PLAYER_MEMORY');
  const requestedDate = String.fromEnvironment('PLAYER_MEMORY_DATE');
  const localLocation = String.fromEnvironment('PLAYER_MEMORY_FILE');
  const streamFixture = bool.fromEnvironment('PLAYER_MEMORY_STREAM');

  testWidgets(
    'long programme survives upstream buffering and session replacement',
    (tester) async {
      final services = await bootstrapServices();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await services.dispose();
      });
      await tester.pumpWidget(SctvApp(services: services));

      HttpServer? fixtureServer;
      if (localLocation.isNotEmpty && streamFixture) {
        expect(localLocation, startsWith('documents:'));
        final documents = await getApplicationDocumentsDirectory();
        final file = File('${documents.path}/${localLocation.substring(10)}');
        fixtureServer = await _serveFixture(file);
        addTearDown(() => fixtureServer!.close(force: true));
      }

      Future<void> waitFor(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
        expect(tester.takeException(), isNull);
      }

      await waitFor(() => services.library.hasSnapshot);
      late final PlaybackInput input;
      if (localLocation.isNotEmpty) {
        input = const PlaybackInput(
          title: 'High-bitrate local fixture',
          sources: [],
          localLocation: localLocation,
        );
      } else {
        final programme = services.library.programmes.firstWhere(
          (p) => p.id == '1',
        );
        final dates = await services.programmes.refreshDates(programme.id);
        final date = requestedDate.isEmpty
            ? dates.items.first
            : dates.items.firstWhere((date) => date.date == requestedDate);
        final contents = await services.programmes.refreshContents(
          programme.id,
          date.id,
        );
        final content = contents.items.firstWhere(
          (item) => isFullEpisode(item.title, programme.name, date.date),
        );
        final sources = videoSources(content);
        expect(sources, isNotEmpty);
        final selection = ProgrammeSelection(
          programme: programme,
          broadcast: date,
          content: content,
        );
        input = PlaybackInput(
          title: content.title,
          sources: sources,
          selection: selection,
        );
      }
      final backend = _RecordingBackend(services.playback);
      final navigator = Navigator.of(
        tester.element(find.byType(Scaffold).first),
      );

      Future<void> hold(
        PlaybackSession session,
        String phase,
        int seconds,
      ) async {
        debugPrint('PLAYER_MEMORY_PHASE $phase ${session.value.position}');
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(session.value.error, isNull);
          expect(tester.takeException(), isNull);
        }
      }

      for (var cycle = 0; cycle < 3; cycle++) {
        final previous = backend.session;
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (context) => PlayerPage(
                key: ValueKey(cycle),
                input: PlaybackInput(
                  title: input.title,
                  sources: input.sources,
                  selection: input.selection,
                  localLocation: input.localLocation,
                  initialPosition: Duration(
                    seconds: cycle * (localLocation.isEmpty ? 120 : 30),
                  ),
                ),
                backend: backend,
                history: services.history,
                surfaceBuilder: (session) => PlaybackSurface(session: session),
              ),
            ),
          ),
        );
        await waitFor(
          () => backend.session != null && backend.session != previous,
        );
        final session = backend.session!;
        if (fixtureServer != null) {
          // The controlled server uses the same public network API as the
          // production adapter. Keep URL-policy exceptions inside this test.
          await tester.pump();
          final engine = tester
              .widget<BetterPlayer>(find.byType(BetterPlayer))
              .controller;
          await engine.setupDataSource(
            BetterPlayerDataSource.network(
              'http://127.0.0.1:${fixtureServer.port}/stress.mp4',
              videoFormat: BetterPlayerVideoFormat.other,
            ),
          );
          await session.seek(Duration(seconds: cycle * 30));
          await session.pause();
          debugPrint('PLAYER_MEMORY_STREAM $cycle');
        }
        expect(
          session.value.duration,
          greaterThan(Duration(minutes: localLocation.isEmpty ? 15 : 2)),
        );
        expect(session.value.playing, isFalse);
        debugPrint(
          'PLAYER_MEMORY_OPEN $cycle ${input.title} ${session.value.duration}',
        );

        await hold(session, 'paused-$cycle', cycle == 0 ? 90 : 15);
        final before = session.value.position;
        await session.play();
        await hold(session, 'playing-$cycle', cycle == 0 ? 90 : 15);
        expect(
          session.value.position,
          greaterThan(before + const Duration(seconds: 5)),
        );

        if (cycle == 0) {
          final seek = localLocation.isEmpty
              ? const Duration(minutes: 7)
              : const Duration(seconds: 90);
          await session.seek(seek);
          await hold(session, 'seek', 30);
          expect(session.value.position, greaterThan(seek));
          if (input.sources.length > 1) {
            final beforeSwitch = session.value.position;
            await session.selectSource(input.sources.last);
            await hold(session, 'quality', 30);
            expect(session.value.source, input.sources.last);
            expect(session.value.position, greaterThan(beforeSwitch));
          } else {
            debugPrint('PLAYER_MEMORY_SINGLE_SOURCE');
          }
        }

        await session.pause();
        navigator.pop();
        await tester.pumpAndSettle();
        await session.dispose();
        debugPrint('PLAYER_MEMORY_CLOSED $cycle');
      }
      await tester.pumpWidget(const SizedBox());

      // Leave a sampling window after native disposal before the test exits.
      debugPrint('PLAYER_MEMORY_RELEASED');
      await Future<void>.delayed(const Duration(seconds: 10));
      debugPrint('PLAYER_MEMORY_PASS');
    },
    skip: !enabled || !(Platform.isAndroid || Platform.isIOS),
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

class _RecordingBackend implements PlaybackBackend {
  _RecordingBackend(this.delegate);

  final PlaybackBackend delegate;
  PlaybackSession? session;

  @override
  Future<PlaybackSession> open(PlaybackInput input) async =>
      session = await delegate.open(input);
}

Future<HttpServer> _serveFixture(File file) async {
  final length = await file.length();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      final range = RegExp(r'bytes=(\d+)-(\d*)')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      final start = int.parse(range?[1] ?? '0');
      final end =
          int.tryParse(range?[2] ?? '')?.clamp(0, length - 1) ?? length - 1;
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (start >= length || start > end) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      } else {
        if (range != null) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$length',
          );
        }
        request.response.contentLength = end - start + 1;
        // Stream with backpressure: retaining the whole fixture in Dart would
        // measure the test server's allocations rather than native buffering.
        if (request.method != 'HEAD') {
          await request.response.addStream(file.openRead(start, end + 1));
        }
      }
      await request.response.close();
    } on SocketException {
      // Seeking and session disposal intentionally cancel in-flight responses.
    } on HttpException {
      // A closed fixture request is expected during native source replacement.
    }
  });
  return server;
}

import 'dart:async';

import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';

const standard = VideoSource(
  quality: VideoQuality.standard,
  url: 'https://media.example/standard.mp4',
);
const smooth = VideoSource(
  quality: VideoQuality.smooth,
  url: 'https://media.example/smooth.mp4',
);
const selection = ProgrammeSelection(
  programme: Programme(id: '1', name: 'Programme'),
  broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
  content: ProgrammeContent(id: '3', title: 'Title'),
);
const input = PlaybackInput(
  title: 'Title',
  sources: [standard, smooth],
  selection: selection,
);

class FakeBackend implements PlaybackBackend {
  FakeBackend(this.session);
  final PlaybackSession session;
  @override
  Future<PlaybackSession> open(PlaybackInput input) async => session;
}

class SequenceBackend implements PlaybackBackend {
  SequenceBackend(this.sessions);
  final List<FakeSession> sessions;
  var next = 0;
  @override
  Future<PlaybackSession> open(PlaybackInput input) async {
    final session = sessions[next++];
    session.emit(position: input.initialPosition);
    return session;
  }
}

class DelayedBackend implements PlaybackBackend {
  DelayedBackend(this.result);
  final Future<PlaybackSession> result;
  @override
  Future<PlaybackSession> open(PlaybackInput input) => result;
}

class FakeSession implements PlaybackSession {
  final events = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  @override
  final id = 'fake';
  @override
  PlaybackSnapshot value = const PlaybackSnapshot(
    initialized: true,
    source: standard,
    duration: Duration(seconds: 100),
    supportsPip: true,
  );
  int playCalls = 0;
  int seekCalls = 0;
  int pauseCalls = 0;
  int disposeCalls = 0;
  bool failSwitch = false;
  bool failPause = false;
  Future<void>? disposeDelay;
  Future<void>? pipResult;

  /// Publishes a snapshot as if it came from the playback adapter.
  void emit({
    bool playing = false,
    bool inPip = false,
    bool buffering = false,
    Duration? duration = const Duration(seconds: 100),
    Duration position = Duration.zero,
    double speed = 1,
    bool initialized = true,
    String? error,
  }) {
    value = PlaybackSnapshot(
      initialized: initialized,
      error: error,
      speed: speed,
      source: standard,
      duration: duration,
      playing: playing,
      inPip: inPip,
      buffering: buffering,
      position: position,
      supportsPip: true,
    );
    events.add(value);
  }

  @override
  Stream<PlaybackSnapshot> get changes => events.stream;
  @override
  Future<void> play() async {
    playCalls++;
    emit(playing: true, position: value.position, speed: value.speed);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    if (failPause) {
      throw StateError('Pause failed');
    }

    emit(position: value.position, speed: value.speed);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    emit(position: position);
  }

  @override
  Future<void> setSpeed(double speed) async => emit(
    playing: value.playing,
    position: value.position,
    inPip: value.inPip,
    speed: speed,
  );
  @override
  Future<void> selectSource(VideoSource source) async {
    if (failSwitch) {
      throw StateError('unavailable');
    }
  }

  @override
  Future<void> enterPictureInPicture() async {
    if (pipResult case final Future<void> pending) {
      await pending;
      return;
    }
    emit(playing: true, inPip: true);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeDelay;
    await events.close();
  }
}

class MemoryHistory implements HistoryRepository {
  final entries = <ViewingEntry>[];
  @override
  SaveViewingCheckpoint openSession(ContentRef ref) =>
      (entry) async => entries.add(entry);
  @override
  Future<List<ViewingEntry>> loadHistory() async => entries;
  @override
  Stream<List<ViewingEntry>> watchHistory() => const Stream.empty();
  @override
  Future<void> remove(ContentRef ref) async {}
  @override
  Future<void> clear() async => entries.clear();
}

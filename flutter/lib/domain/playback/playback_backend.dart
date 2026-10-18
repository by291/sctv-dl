import '../programmes/programme.dart';

class PlaybackInput {
  const PlaybackInput({
    required this.title,
    required this.sources,
    this.selection,
    this.localLocation,
    this.preferredQuality,
    this.initialPosition = Duration.zero,
  });

  final String title;
  final List<VideoSource> sources;
  final ProgrammeSelection? selection;
  final String? localLocation;
  final VideoQuality? preferredQuality;
  final Duration initialPosition;
}

class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.initialized = false,
    this.firstFrameRendered = false,
    this.playing = false,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration,
    this.speed = 1,
    this.source,
    this.error,
    this.supportsPip = false,
    this.inPip = false,
    this.ended = false,
  });

  final bool initialized;

  /// The native output has produced a frame, independently of metadata readiness.
  final bool firstFrameRendered;
  final bool playing;
  final bool buffering;

  final Duration position;
  final Duration? duration;
  final double speed;
  final VideoSource? source;
  final String? error;

  final bool supportsPip;
  final bool inPip;
  final bool ended;
}

abstract interface class PlaybackBackend {
  Future<PlaybackSession> open(PlaybackInput input);
}

abstract interface class PlaybackSession {
  String get id;
  PlaybackSnapshot get value;
  Stream<PlaybackSnapshot> get changes;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> selectSource(VideoSource source);
  Future<void> enterPictureInPicture();

  Future<void> dispose();
}

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

/// Opens an independently owned playback session for an accepted input.
abstract interface class PlaybackBackend {
  /// Opens the input at its initial position in a paused state.
  Future<PlaybackSession> open(PlaybackInput input);
}

/// Controls one native playback allocation and observes its current state.
abstract interface class PlaybackSession {
  String get id;
  PlaybackSnapshot get value;
  Stream<PlaybackSnapshot> get changes;

  /// Requests playback for the current source.
  Future<void> play();

  /// Pauses playback while retaining the current position.
  Future<void> pause();

  /// Moves playback to the requested position.
  Future<void> seek(Duration position);

  /// Sets the desired playback rate.
  Future<void> setSpeed(double speed);

  /// Switches to another accepted source at the current position.
  Future<void> selectSource(VideoSource source);

  /// Requests the platform's picture-in-picture window.
  Future<void> enterPictureInPicture();

  /// Releases native playback and closes session observation.
  Future<void> dispose();
}

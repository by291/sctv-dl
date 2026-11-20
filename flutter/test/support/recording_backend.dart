import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/platform/playback/video_player_backend.dart';

/// Records native playback sessions so integration tests can compare their identity.
class RecordingBackend implements PlaybackBackend {
  final _delegate = VideoPlayerBackend();

  PlaybackSession? session;
  int opens = 0;

  @override
  Future<PlaybackSession> open(PlaybackInput input) async {
    opens++;
    final opened = await _delegate.open(input);
    session = opened;

    return opened;
  }
}

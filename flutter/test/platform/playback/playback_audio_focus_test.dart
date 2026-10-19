import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/platform/playback/playback_audio_focus.dart';

void main() {
  test('returning to the previous focus owner does not deadlock a superseded transfer', () async {
    final native = AudioFixture();
    late PlaybackAudioFocus first;
    late PlaybackAudioFocus second;
    first = PlaybackAudioFocus(
      native,
      pause: () => first.deactivate(),
      onError: (_, _) {},
    );
    second = PlaybackAudioFocus(
      native,
      pause: () => second.deactivate(),
      onError: (_, _) {},
    );
    await first.activate();
    final transferring = second.activate();
    final rejected = expectLater(transferring, throwsStateError);
    await first.activate().timeout(const Duration(seconds: 1));
    await rejected;
    await second.dispose();
    await first.dispose();
    expect(native.active, [true, true, false]);
    await native.close();
  });
  test(
    'concurrent activation transfers ownership without two audible sessions',
    () async {
      final native = AudioFixture();
      final gate = Completer<void>();
      native.activationGate = gate.future;
      var firstPaused = false;
      late PlaybackAudioFocus first;
      first = PlaybackAudioFocus(
        native,
        pause: () async {
          firstPaused = true;
          await first.deactivate();
        },
        onError: (_, _) {},
      );
      final second = PlaybackAudioFocus(
        native,
        pause: () async {},
        onError: (_, _) {},
      );
      final openingFirst = first.activate();
      final firstRejected = expectLater(openingFirst, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final openingSecond = second.activate();
      gate.complete();
      await firstRejected;
      await openingSecond;
      expect(firstPaused, isTrue);
      expect(native.active, [true, true]);
      await first.dispose();
      expect(native.active, [true, true]);
      await second.dispose();
      expect(native.active, [true, true, false]);
      await native.close();
    },
  );
  test(
    'interruptions and route loss pause once without resuming on recovery',
    () async {
      final native = AudioFixture();
      var pauses = 0;
      final errors = <Object>[];
      final focus = PlaybackAudioFocus(
        native,
        pause: () async {
          pauses++;
        },
        onError: (error, _) => errors.add(error),
      );
      await focus.configure();
      await focus.activate();
      native.interruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await Future<void>.delayed(Duration.zero);
      expect(pauses, 1);
      native.interruptions.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await Future<void>.delayed(Duration.zero);
      expect(pauses, 1);
      native.noisy.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(pauses, 2);
      await focus.dispose();
      native.noisy.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(pauses, 2);
      expect(native.active, [true, false]);
      expect(errors, isEmpty);
      await native.close();
    },
  );

  test('denied focus never grants playback ownership', () async {
    final native = AudioFixture()..allow = false;
    var pauses = 0;
    final focus = PlaybackAudioFocus(
      native,
      pause: () async {
        pauses++;
      },
      onError: (_, _) {},
    );
    await expectLater(focus.activate(), throwsStateError);
    native.noisy.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(pauses, 0);
    await focus.dispose();
    expect(native.active, [true]);
    await native.close();
  });
}

class AudioFixture extends Fake implements AudioSession {
  final interruptions = StreamController<AudioInterruptionEvent>.broadcast();
  final noisy = StreamController<void>.broadcast();
  final active = <bool>[];
  bool allow = true;
  Future<void>? activationGate;

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      interruptions.stream;
  @override
  Stream<void> get becomingNoisyEventStream => noisy.stream;
  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {}
  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    this.active.add(active);
    if (active) {
      final gate = activationGate;
      activationGate = null;
      await gate;
    }
    return allow;
  }

  Future<void> close() async {
    await interruptions.close();
    await noisy.close();
  }
}

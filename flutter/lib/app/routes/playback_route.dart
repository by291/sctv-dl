import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/state_panel.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_repository.dart';
import '../../features/player/player_page.dart';
import '../../platform/playback/better_player_backend.dart';
import '../../platform/playback/native_player_environment.dart';
import '../playback_input_resolver.dart';
import '../providers.dart';
import '../services.dart';
import 'route_error.dart';

sealed class PlaybackTarget {
  const PlaybackTarget();
}

final class OnlinePlaybackTarget extends PlaybackTarget {
  const OnlinePlaybackTarget(this.contentRef);

  final ContentRef contentRef;
}

final class LocalPlaybackTarget extends PlaybackTarget {
  const LocalPlaybackTarget(this.taskId);

  final String taskId;
}

class PlaybackRoute extends ConsumerStatefulWidget {
  const PlaybackRoute({
    super.key,
    required this.services,
    required this.target,
    this.onDownload,
    this.acceptedInput,
  });

  final AppServices services;
  final PlaybackTarget target;
  final PlaybackInput? acceptedInput;
  final Future<void> Function(BuildContext, ProgrammeSelection)? onDownload;

  @override
  ConsumerState<PlaybackRoute> createState() => _PlaybackRouteState();
}

class _PlaybackRouteState extends ConsumerState<PlaybackRoute> {
  late Future<PlaybackInput> input = widget.acceptedInput == null
      ? _resolve()
      : Future.value(widget.acceptedInput);
  RequestScope? _request;

  Future<PlaybackInput> _resolve() async {
    _request?.cancel();
    final scope = RequestScope();
    _request = scope;

    final resolver = PlaybackInputResolver(
      widget.services.programmes,
      widget.services.history,
      widget.services.downloads,
    );

    return switch (widget.target) {
      OnlinePlaybackTarget(:final contentRef) => resolver.online(
        contentRef,
        scope,
        ref.read(preferencesProvider).value.quality,
      ),
      LocalPlaybackTarget(:final taskId) => resolver.local(taskId, scope),
    };
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PlaybackInput>(
    future: input,
    initialData: widget.acceptedInput,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return routeError(
          context,
          '${snapshot.error}',
          () => setState(() => input = _resolve()),
          returnLocation: widget.target is LocalPlaybackTarget
              ? '/downloads'
              : '/',
        );
      }
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: const Text('节目播放')),
          body: const PageSkeleton(),
        );
      }

      final prepared = snapshot.data!;
      return PlayerPage(
        input: prepared,
        environment: NativePlayerEnvironment(),
        systemVolume: Platform.isIOS ? const NativeSystemVolume() : null,
        backend: widget.services.playback,
        surfaceBuilder: (session) => PlaybackSurface(session: session),
        history: widget.services.history,
        onDownload:
            prepared.localLocation != null ||
                prepared.selection == null ||
                widget.onDownload == null
            ? null
            : () => widget.onDownload!(context, prepared.selection!),
      );
    },
  );
}

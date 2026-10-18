import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/state_panel.dart';
import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_repository.dart';
import '../../features/programmes/archive_controller.dart';
import '../../features/programmes/archive_page.dart';
import '../playback_input_resolver.dart';
import '../services.dart';
import 'route_error.dart';

class ArchiveRoute extends StatefulWidget {
  const ArchiveRoute({
    super.key,
    required this.services,
    required this.programmeId,
    required this.onPlay,
    required this.onDownload,
    this.acceptedProgramme,
    this.coverTag,
  });

  final AppServices services;
  final String programmeId;
  final Programme? acceptedProgramme;
  final String? coverTag;
  final Future<void> Function(BuildContext, ProgrammeSelection) onPlay;

  // Modal actions need the mounted page context below the route's Navigator.
  final Future<void> Function(BuildContext, List<ProgrammeSelection>)
  onDownload;

  @override
  State<ArchiveRoute> createState() => _ArchiveRouteState();
}

class _ArchiveRouteState extends State<ArchiveRoute> {
  late Future<Programme> programme = widget.acceptedProgramme == null
      ? _resolve()
      : Future.value(widget.acceptedProgramme);
  RequestScope? _request;
  ArchiveController? controller;

  Future<Programme> _resolve() {
    _request?.cancel();
    final scope = RequestScope();
    _request = scope;

    return PlaybackInputResolver(
      widget.services.programmes,
      widget.services.history,
      widget.services.downloads,
    ).programme(widget.programmeId, scope: scope);
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Programme>(
    future: programme,
    initialData: widget.acceptedProgramme,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return routeError(
          context,
          '${snapshot.error}',
          () => setState(() => programme = _resolve()),
        );
      }
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: const Text('往期回看')),
          body: const PageSkeleton(),
        );
      }

      controller ??= ArchiveController(
        repository: widget.services.programmes,
        programme: snapshot.data!,
      );

      return ArchivePage(
        coverTag: widget.coverTag,
        controller: controller!,
        library: widget.services.library,
        onPlay: (selection) => unawaited(widget.onPlay(context, selection)),
        onDownload: (items) => widget.onDownload(context, items),
        onOpenProgramme: (item) =>
            context.replace('/programme/${item.id}', extra: item),
      );
    },
  );
}

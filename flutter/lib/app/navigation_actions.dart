import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/programmes/programme.dart';
import '../features/programmes/download_quality_sheet.dart';
import 'playback_input_resolver.dart';
import 'providers.dart';
import 'services.dart';

class AppNavigationActions {
  AppNavigationActions(this.services)
    : resolver = PlaybackInputResolver(
        services.programmes,
        services.history,
        services.downloads,
      );

  final AppServices services;
  final PlaybackInputResolver resolver;

  Future<void> download(
    BuildContext context,
    List<ProgrammeSelection> selections,
  ) async {
    final router = GoRouter.of(context);
    final preferences = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(preferencesProvider).value;

    final result = await showDownloadQualitySheet(
      context,
      selections: selections,
      downloads: services.downloads,
      wifiOnly: preferences.wifiOnly,
      wifiPolicyLabel: Platform.isIOS ? '禁用蜂窝网络' : '仅使用 Wi-Fi',
    );

    if (result != null && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          persist: false,
          content: Text(downloadResultLabel(result)),
          action: SnackBarAction(
            label: '查看下载',
            onPressed: () {
              messenger.removeCurrentSnackBar();
              router.go('/downloads');
            },
          ),
        ),
      );
    }
  }

  Future<void> play(
    BuildContext context,
    ProgrammeSelection selection, {
    Duration? position,
  }) async {
    final Duration resume;
    try {
      resume = position ?? await resolver.resumePosition(selection.ref);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法读取观看进度：$error')));
      }
      return;
    }
    if (!context.mounted) return;

    final quality = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(preferencesProvider).value.quality;
    final ref = selection.ref;

    await context.push(
      '/play/${ref.programmeId}/${ref.dateId}/${ref.contentId}',
      extra: resolver.acceptedOnline(
        selection,
        quality: quality,
        position: resume,
      ),
    );
  }

  Future<void> openProgramme(
    BuildContext context,
    Programme programme, {
    bool featured = false,
  }) async {
    await context.push(
      '/programme/${programme.id}',
      extra: (
        programme: programme,
        coverTag: '${featured ? 'exploration' : 'catalogue'}-${programme.id}',
      ),
    );

    if (context.mounted) unawaited(services.library.refresh());
  }
}

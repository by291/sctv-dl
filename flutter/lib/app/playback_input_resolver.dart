import '../domain/downloads/download_repository.dart';
import '../domain/downloads/download_task.dart';
import '../domain/downloads/file_gateway.dart';
import '../domain/playback/history_repository.dart';
import '../domain/playback/playback_backend.dart';
import '../domain/programmes/programme.dart';
import '../domain/programmes/programme_policy.dart';
import '../domain/programmes/programme_repository.dart';

/// Resolves restored IDs without changing the accepted input of an active route.
class PlaybackInputResolver {
  const PlaybackInputResolver(this.programmes, this.history, this.downloads);

  final ProgrammeRepository programmes;
  final HistoryRepository history;
  final DownloadRepository downloads;

  Future<Programme> programme(String id, {required RequestScope scope}) async {
    scope.throwIfCancelled();
    if (!RegExp(r'^\d+$').hasMatch(id)) throw const FormatException('栏目编号无效');

    final cached = await programmes.cachedProgrammes();
    scope.throwIfCancelled();

    final existing = cached?.items.where((item) => item.id == id).firstOrNull;
    if (existing != null) return existing;

    final fresh = await programmes.refreshProgrammes(scope: scope);
    scope.throwIfCancelled();

    return fresh.items.where((item) => item.id == id).firstOrNull ??
        (throw StateError('栏目已不可用'));
  }

  Future<Duration> resumePosition(
    ContentRef contentRef, {
    RequestScope? scope,
  }) async {
    scope?.throwIfCancelled();
    final entries = await history.loadHistory();
    scope?.throwIfCancelled();

    final previous = entries
        .where((entry) => entry.selection.ref == contentRef)
        .firstOrNull;
    return previous == null || previous.completed
        ? Duration.zero
        : previous.position;
  }

  Future<PlaybackInput> online(
    ContentRef contentRef,
    RequestScope scope,
    VideoQuality quality,
  ) async {
    if (![
      contentRef.programmeId,
      contentRef.dateId,
      contentRef.contentId,
    ].every((id) => RegExp(r'^\d+$').hasMatch(id))) {
      throw const FormatException('节目编号无效');
    }

    final selectedProgramme = await programme(
      contentRef.programmeId,
      scope: scope,
    );
    scope.throwIfCancelled();

    var dates = await programmes.cachedDates(contentRef.programmeId);
    scope.throwIfCancelled();
    dates ??= await programmes.refreshDates(
      contentRef.programmeId,
      scope: scope,
    );
    scope.throwIfCancelled();

    final date = dates.items
        .where((date) => date.id == contentRef.dateId)
        .firstOrNull;
    if (date == null) throw StateError('播出日期已不可用');

    var contents = await programmes.cachedContents(
      contentRef.programmeId,
      contentRef.dateId,
    );
    scope.throwIfCancelled();
    contents ??= await programmes.refreshContents(
      contentRef.programmeId,
      contentRef.dateId,
      scope: scope,
    );
    scope.throwIfCancelled();

    final content = contents.items
        .where((item) => item.id == contentRef.contentId)
        .firstOrNull;
    if (content == null) throw StateError('节目已不可用');

    final position = await resumePosition(contentRef, scope: scope);
    scope.throwIfCancelled();

    return acceptedOnline(
      ProgrammeSelection(
        programme: selectedProgramme,
        broadcast: date,
        content: content,
      ),
      quality: quality,
      position: position,
    );
  }

  PlaybackInput acceptedOnline(
    ProgrammeSelection selection, {
    required VideoQuality quality,
    required Duration position,
  }) {
    final sources = videoSources(selection.content).toList()
      ..sort(
        (a, b) => (a.quality == quality ? 0 : 1).compareTo(
          b.quality == quality ? 0 : 1,
        ),
      );

    return PlaybackInput(
      title: selection.content.title,
      sources: List.unmodifiable(sources),
      preferredQuality: quality,
      selection: selection,
      initialPosition: position,
    );
  }

  Future<PlaybackInput> local(String taskId, RequestScope scope) async {
    // Reconciliation checks the durable task's actual file before local restore.
    // Missing local media never resolves through the online programme endpoint.
    await downloads.reconcile();
    scope.throwIfCancelled();

    final tasks = await downloads.loadTasks();
    scope.throwIfCancelled();

    final task = tasks.where((task) => task.id == taskId).firstOrNull;
    final location = task?.fileLocation;
    if (task == null ||
        task.state != DownloadState.completed ||
        location == null) {
      throw StateError('下载文件已不可用，请返回下载列表重新下载');
    }
    DownloadFileLocation.parse(location);

    final position = await resumePosition(task.selection.ref, scope: scope);
    scope.throwIfCancelled();

    return PlaybackInput(
      title: task.selection.content.title,
      sources: const [],
      selection: task.selection,
      localLocation: location,
      initialPosition: position,
    );
  }
}

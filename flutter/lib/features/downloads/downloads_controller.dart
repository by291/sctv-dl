import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/downloads/download_repository.dart';
import '../../domain/downloads/download_task.dart';
import 'download_management.dart';

enum DownloadBatchPhase { idle, confirming, running }

/// Owns selection and action state. Widgets only derive presentation from it;
/// native task updates prune selection before the corresponding list is built.
class DownloadsController extends ChangeNotifier {
  DownloadsController(this.repository);

  final DownloadRepository repository;

  final _pending = <String>{};
  final _selected = <String>{};
  DownloadFilter _filter = DownloadFilter.all;
  bool _selecting = false;

  DownloadBatchPhase _batchPhase = DownloadBatchPhase.idle;

  bool _disposed = false;

  Set<String> get pending => Set.unmodifiable(_pending);
  Set<String> get selected => Set.unmodifiable(_selected);
  DownloadFilter get filter => _filter;
  bool get selecting => _selecting;

  DownloadBatchPhase get batchPhase => _batchPhase;
  bool get batchBusy => _batchPhase != DownloadBatchPhase.idle;

  Stream<List<DownloadTask>> watchTasks() => repository.watchTasks().map((
    tasks,
  ) {
    _selected.retainAll(tasks.where(_filter.includes).map((task) => task.id));
    return tasks;
  });

  List<DownloadTask> visibleTasks(List<DownloadTask> tasks) =>
      tasks.where(_filter.includes).toList()..sort((a, b) {
        final creationOrder = b.createdAt.compareTo(a.createdAt);
        return creationOrder != 0 ? creationOrder : a.id.compareTo(b.id);
      });

  void enterSelection() {
    _selecting = true;
    notifyListeners();
  }

  void leaveSelection() {
    if (batchBusy) return;

    _selecting = false;
    _selected.clear();
    notifyListeners();
  }

  void toggleSelection(DownloadTask task) {
    if (batchBusy) return;

    _selecting = true;
    if (!_selected.add(task.id)) _selected.remove(task.id);
    notifyListeners();
  }

  void changeFilter(DownloadFilter filter) {
    if (batchBusy) return;

    _filter = filter;
    _selected.clear();
    notifyListeners();
  }

  void toggleAll(List<DownloadTask> visible) {
    if (batchBusy) return;

    if (visible.every((task) => _selected.contains(task.id))) {
      _selected.clear();
    } else {
      _selected.addAll(visible.map((task) => task.id));
    }
    notifyListeners();
  }

  Future<void> perform(String id, Future<void> Function() action) async {
    if (!_pending.add(id)) return;
    notifyListeners();

    try {
      await action();
    } finally {
      _pending.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<DownloadActionResult?> runBatch(
    DownloadAction action,
    List<DownloadTask> selected,
    Future<bool> Function(List<DownloadTask>) confirm,
  ) async {
    if (batchBusy || _pending.isNotEmpty) return null;

    final targets = selected.where(action.supports).toList();
    if (targets.isEmpty) return null;

    _batchPhase = DownloadBatchPhase.confirming;
    notifyListeners();

    try {
      if (!await confirm(targets) || _disposed) return null;

      _batchPhase = DownloadBatchPhase.running;
      notifyListeners();

      final result = await runDownloadBatch(repository, action, targets);

      _selected.removeAll(result.succeeded);
      _selected.removeAll(result.skipped);
      return result;
    } finally {
      _batchPhase = DownloadBatchPhase.idle;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';

import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_policy.dart';
import '../../domain/programmes/programme_repository.dart';

class ArchiveController extends ChangeNotifier {
  ArchiveController({required this.repository, required this.programme});

  final ProgrammeRepository repository;
  final Programme programme;
  ProgrammeSnapshot<BroadcastDate>? _dates;
  ProgrammeSnapshot<BroadcastDate>? _pendingDates;
  ProgrammeSnapshot<ProgrammeContent>? _contents;
  ProgrammeSnapshot<ProgrammeContent>? _pendingContents;
  RequestScope? _dateScope;
  RequestScope? _contentScope;
  int _contentGeneration = 0;
  bool _disposed = false;
  String? _initialDateId;
  bool _checkingDates = false;
  bool _checkingContents = false;
  bool loadingDates = true;
  bool loadingContents = true;
  String? _dateError;
  String? _contentError;
  BroadcastDate? selectedDate;
  bool selectionMode = false;
  final Set<String> selectedIds = {};
  bool ascending = true;

  List<BroadcastDate> get dates => _dates?.items ?? const [];
  List<ProgrammeContent> get contents => _contents?.items ?? const [];
  bool get hasSnapshot => _contents != null;
  bool get hasPendingUpdate =>
      _pendingDates != null || _pendingContents != null;
  String? get error => _dateError ?? _contentError;
  List<ProgrammeContent> get fullEpisodes => contents
      .where(
        (item) =>
            isFullEpisode(item.title, programme.name, selectedDate?.date ?? ''),
      )
      .toList();
  List<ProgrammeContent> get clips => orderClips(
    contents
        .where(
          (item) => !isFullEpisode(
            item.title,
            programme.name,
            selectedDate?.date ?? '',
          ),
        )
        .toList(),
    ascending: ascending,
  );
  List<ProgrammeSelection> get selectedItems => selectedDate == null
      ? []
      : [
          for (final item in contents)
            if (selectedIds.contains(item.id))
              ProgrammeSelection(
                programme: programme,
                broadcast: selectedDate!,
                content: item,
              ),
        ];

  Future<void> initialize({String? dateId}) async {
    _initialDateId = dateId;
    try {
      final cached = await repository.cachedDates(programme.id);
      if (_disposed) return;
      if (cached != null) {
        _dates = cached;
        loadingDates = false;
        notifyListeners();
        final selected =
            dates.where((date) => date.id == dateId).firstOrNull ??
            dates.firstOrNull;
        if (selected != null) await selectDate(selected);
      }
    } catch (failure) {
      if (_disposed) return;
      _dateError = '缓存读取失败：$failure';
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    await _refreshDates();
    if (selectedDate != null && !_disposed) await _refreshContents();
  }

  Future<void> _refreshDates() async {
    if (_checkingDates || _disposed) return;
    _checkingDates = true;
    final scope = RequestScope();
    _dateScope = scope;
    try {
      final result = await repository.refreshDates(programme.id, scope: scope);
      if (_disposed || scope.isCancelled) return;
      _dateError = null;
      if (_dates == null) {
        _dates = result;
        loadingDates = false;
        final first =
            dates.where((date) => date.id == _initialDateId).firstOrNull ??
            dates.firstOrNull;
        if (first != null) {
          await selectDate(first);
        } else {
          loadingContents = false;
        }
      } else {
        _pendingDates = result.revision == _dates!.revision ? null : result;
      }
    } on RequestCancelled {
      // A cancelled destination must not publish a failure over its replacement.
    } catch (failure) {
      if (!_disposed && !scope.isCancelled) _dateError = '播出日期加载失败：$failure';
    } finally {
      _checkingDates = false;
      if (!_disposed) {
        loadingDates = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectDate(BroadcastDate date) async {
    if (_disposed || selectedDate?.id == date.id) return;
    _contentScope?.cancel();
    final generation = ++_contentGeneration;
    _checkingContents = false;
    selectedDate = date;
    _contents = null;
    _pendingContents = null;
    selectedIds.clear();
    selectionMode = false;
    loadingContents = true;
    _contentError = null;
    notifyListeners();
    try {
      final cached = await repository.cachedContents(programme.id, date.id);
      if (_disposed || generation != _contentGeneration) return;
      if (cached != null) {
        _contents = cached;
        loadingContents = false;
        notifyListeners();
      }
    } catch (failure) {
      if (_disposed || generation != _contentGeneration) return;
      _contentError = '缓存读取失败：$failure';
    }
    await _refreshContents();
  }

  Future<void> _refreshContents() async {
    final date = selectedDate;
    if (date == null || _checkingContents || _disposed) return;
    _checkingContents = true;
    final generation = _contentGeneration;
    final scope = RequestScope();
    _contentScope = scope;
    try {
      final result = await repository.refreshContents(
        programme.id,
        date.id,
        scope: scope,
      );
      if (_disposed || scope.isCancelled || generation != _contentGeneration) {
        return;
      }
      _contentError = null;
      if (_contents == null) {
        _contents = result;
      } else {
        _pendingContents = result.revision == _contents!.revision
            ? null
            : result;
      }
    } on RequestCancelled {
      // Generation checks also reject sources that cannot cancel promptly.
    } catch (failure) {
      if (!_disposed &&
          !scope.isCancelled &&
          generation == _contentGeneration) {
        _contentError = '节目内容加载失败：$failure';
      }
    } finally {
      if (!_disposed && generation == _contentGeneration) {
        _checkingContents = false;
        loadingContents = false;
        notifyListeners();
      }
    }
  }

  void acceptUpdates() {
    if (_disposed || selectionMode) return;
    if (_pendingDates case final update?) {
      _dates = update;
      _pendingDates = null;
      final current = dates
          .where((date) => date.id == selectedDate?.id)
          .firstOrNull;
      if (current != null) selectedDate = current;
      if (current == null) {
        _contentScope?.cancel();
        _contentGeneration++;
        selectedDate = null;
        _contents = null;
        _pendingContents = null;
        final first = dates.firstOrNull;
        if (first != null) {
          // selectDate owns the new key's cache/request lifecycle.
          selectDate(first);
        } else {
          loadingContents = false;
        }
      }
    }
    if (_pendingContents case final update?) {
      _contents = update;
      _pendingContents = null;
    }
    notifyListeners();
  }

  void enterSelection() {
    selectionMode = true;
    notifyListeners();
  }

  void exitSelection() {
    selectionMode = false;
    selectedIds.clear();
    notifyListeners();
  }

  void toggleSelection(ProgrammeContent item) {
    if (videoSources(item).isEmpty) return;
    selectedIds.contains(item.id)
        ? selectedIds.remove(item.id)
        : selectedIds.add(item.id);
    notifyListeners();
  }

  void selectAll() {
    selectedIds
      ..clear()
      ..addAll(
        contents
            .where((item) => videoSources(item).isNotEmpty)
            .map((item) => item.id),
      );
    notifyListeners();
  }

  void selectFullEpisodes() {
    selectedIds
      ..clear()
      ..addAll(
        fullEpisodes
            .where((item) => videoSources(item).isNotEmpty)
            .map((item) => item.id),
      );
    notifyListeners();
  }

  void toggleSort() {
    if (!selectionMode) {
      ascending = !ascending;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _contentGeneration++;
    _dateScope?.cancel();
    _contentScope?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/settings/user_repository.dart';

/// Confirmed storage values and pending user intent have independent ownership.
class FavouriteController extends ChangeNotifier {
  FavouriteController(this._user, Set<String> initial)
    : _confirmed = {...initial};

  final UserRepository _user;

  Set<String> _confirmed;
  final _pending = <String, ({int revision, bool selected})>{};
  final _failed = <String, ({bool selected, String message})>{};

  StreamSubscription<Set<String>>? _subscription;
  Future<void> _writes = Future.value();
  int _editRevision = 0;
  int _observationGeneration = 0;
  int _observationRevision = 0;
  int _observedValueRevision = 0;

  Future<void>? _retrying;
  String? _observationError;

  bool _disposed = false;

  Set<String> get values {
    final visible = {..._confirmed};
    for (final edit in _pending.entries) {
      edit.value.selected ? visible.add(edit.key) : visible.remove(edit.key);
    }

    return Set.unmodifiable(visible);
  }

  String? get error => _failed.values.firstOrNull?.message ?? _observationError;

  void observe() {
    if (_disposed || _subscription != null) return;

    final generation = ++_observationGeneration;

    void observationFailed(Object error) {
      if (_disposed || generation != _observationGeneration) return;

      _observationRevision++;
      _observationError = '收藏读取失败：$error';
      notifyListeners();
    }

    try {
      _subscription = _user.watchFavourites().listen((value) {
        if (_disposed || generation != _observationGeneration) return;

        _observationRevision++;
        _observedValueRevision++;
        _confirmed = {...value};
        _observationError = null;
        notifyListeners();
      }, onError: observationFailed);
    } catch (error) {
      observationFailed(error);
    }
  }

  Future<void> toggle(String id) => _save(id, !values.contains(id));

  Future<void> _save(String id, bool selected) {
    if (_disposed) return Future.value();

    final edit = (revision: ++_editRevision, selected: selected);
    _pending[id] = edit;
    _failed.remove(id);
    notifyListeners();

    return _writes = _writes.then((_) async {
      if (_disposed || _pending[id] != edit) return;

      try {
        // Retry targets a value, not another toggle. A previous save may have
        // committed even if its acknowledgement or subsequent read failed.
        var stored = await _user.loadFavourites();
        if (_disposed) return;

        _confirmed = {...stored};
        if (stored.contains(id) != selected) {
          await _user.toggleFavourite(id);
          stored = await _user.loadFavourites();
        }
        if (_disposed) return;

        _confirmed = {...stored};
      } catch (failure) {
        if (!_disposed && _pending[id] == edit) {
          _failed[id] = (selected: selected, message: '收藏保存失败：$failure');
        }
      } finally {
        if (!_disposed) {
          if (_pending[id] == edit) _pending.remove(id);
          notifyListeners();
        }
      }
    });
  }

  Future<void> retry() {
    if (_retrying case final pending?) return pending;

    final retrying = _retry();
    _retrying = retrying;

    return retrying.whenComplete(() {
      if (identical(_retrying, retrying)) _retrying = null;
    });
  }

  Future<void> _retry() async {
    if (_disposed) return;

    final failures = Map.of(_failed);
    if (_observationError != null) {
      ++_observationGeneration;
      final previous = _subscription;
      _subscription = null;

      try {
        await previous?.cancel();
      } catch (error) {
        _observationError = '收藏读取失败：$error';
      }
      if (_disposed) return;

      final observationRevision = _observationRevision;
      final valueRevision = _observedValueRevision;
      observe();

      try {
        final stored = await _user.loadFavourites();
        if (_disposed) return;

        // A fresh stream value/error can arrive while this snapshot is loading.
        // Keep the newer observation; a snapshot cannot prove its stream healed.
        if (_observedValueRevision == valueRevision) _confirmed = {...stored};
        if (_observationRevision == observationRevision) {
          _observationError = null;
        }
      } catch (error) {
        if (_observationRevision == observationRevision) {
          _observationError = '收藏读取失败：$error';
        }
      }

      if (!_disposed) notifyListeners();
    }

    for (final failure in failures.entries) {
      // A second retry tap must not replace edits started by the first tap.
      if (_disposed || _failed[failure.key] != failure.value) continue;
      await _save(failure.key, failure.value.selected);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_observationGeneration;

    unawaited(
      _subscription?.cancel().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'favourite observation cleanup',
          ),
        );
      }),
    );

    super.dispose();
  }
}

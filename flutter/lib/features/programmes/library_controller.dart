import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_repository.dart';
import '../../domain/settings/user_repository.dart';
import 'favourite_controller.dart';

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.repository,
    required this.user,
    required Set<String> initialFavourites,
  }) : _favouriteState = FavouriteController(user, initialFavourites),
       _priority = {...initialFavourites} {
    _favouriteState.addListener(notifyListeners);
  }

  final ProgrammeRepository repository;
  final UserRepository user;

  final Set<String> _priority;
  String query = '';
  bool nameOrder = false;
  final _random = Random();

  ProgrammeSnapshot<Programme>? _accepted;
  ProgrammeSnapshot<Programme>? _pending;
  RequestScope? _scope;
  bool _disposed = false;

  bool loading = true;
  bool _refreshing = false;
  String? error;
  String? featuredId;

  final FavouriteController _favouriteState;

  Set<String> get favourites => _favouriteState.values;
  String? get favouriteError => _favouriteState.error;

  List<Programme> get programmes => _accepted?.items ?? const [];
  bool get hasPendingUpdate => _pending != null;
  bool get hasSnapshot => _accepted != null;

  Programme? get featured =>
      programmes.where((p) => p.id == featuredId).firstOrNull;

  Future<void> initialize() async {
    _favouriteState.observe();

    try {
      final cached = await repository.cachedProgrammes();
      if (_disposed) return;

      if (cached != null) _display(cached);
    } catch (failure) {
      if (_disposed) return;

      error = '缓存读取失败：$failure';
    }

    await refresh();
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;

    _refreshing = true;
    final scope = RequestScope();
    _scope = scope;

    try {
      final result = await repository.refreshProgrammes(scope: scope);
      if (_disposed || scope.isCancelled) return;

      error = null;
      if (_accepted == null) {
        _display(result);
      } else {
        _pending = result.revision == _accepted!.revision ? null : result;
      }
    } on RequestCancelled {
      // Cancellation belongs to the page lifecycle, not its error state.
    } catch (failure) {
      if (!_disposed && !scope.isCancelled) error = '节目库加载失败：$failure';
    } finally {
      _refreshing = false;
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _display(ProgrammeSnapshot<Programme> snapshot) {
    _accepted = snapshot;
    loading = false;

    if (!programmes.any((p) => p.id == featuredId)) {
      featuredId = programmes.isEmpty
          ? null
          : programmes[_random.nextInt(programmes.length)].id;
    }
  }

  void acceptUpdate() {
    if (_pending case final snapshot?) {
      _display(snapshot);
      _pending = null;
      notifyListeners();
    }
  }

  void shuffleFeatured() {
    final alternatives = programmes.where((p) => p.id != featuredId).toList();
    if (alternatives.isEmpty) return;

    featuredId = alternatives[_random.nextInt(alternatives.length)].id;
    notifyListeners();
  }

  Future<void> toggleFavourite(String id) => _favouriteState.toggle(id);

  Future<void> retryFavourites() => _favouriteState.retry();

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void toggleSort() {
    nameOrder = !nameOrder;
    notifyListeners();
  }

  List<Programme> visibleProgrammes({bool favouritesOnly = false}) {
    final filter = query.trim().toLowerCase();
    final indexed = programmes.indexed.where((pair) {
      final item = pair.$2;

      return (!favouritesOnly || favourites.contains(item.id)) &&
          item.name.toLowerCase().contains(filter);
    }).toList();

    indexed.sort((left, right) {
      final priority = (_priority.contains(left.$2.id) ? 0 : 1).compareTo(
        _priority.contains(right.$2.id) ? 0 : 1,
      );
      if (priority != 0) return priority;

      final byName = nameOrder ? left.$2.name.compareTo(right.$2.name) : 0;
      return byName == 0 ? left.$1.compareTo(right.$1) : byName;
    });

    return [for (final pair in indexed) pair.$2];
  }

  @override
  void dispose() {
    _disposed = true;
    _scope?.cancel();

    _favouriteState.removeListener(notifyListeners);
    _favouriteState.dispose();

    super.dispose();
  }
}

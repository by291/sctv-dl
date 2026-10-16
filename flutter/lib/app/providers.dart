import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/settings/preferences.dart';
import 'services.dart';

final servicesProvider = Provider<AppServices>(
  (ref) => throw StateError('Application services are not hydrated'),
);

class PreferenceState {
  const PreferenceState(this.value, {this.error});
  final Preferences value;
  final String? error;
}

final preferencesProvider =
    NotifierProvider<PreferencesController, PreferenceState>(
      PreferencesController.new,
    );

class PreferencesController extends Notifier<PreferenceState> {
  int _editRevision = 0;
  @override
  PreferenceState build() =>
      PreferenceState(ref.watch(servicesProvider).initialPreferences);

  Future<void> save(Preferences preferences) async {
    final revision = ++_editRevision;
    state = PreferenceState(preferences);
    try {
      await ref.read(servicesProvider).user.savePreferences(preferences);
    } catch (error) {
      if (ref.mounted && revision == _editRevision) {
        state = PreferenceState(preferences, error: '$error');
      }
    }
  }
}

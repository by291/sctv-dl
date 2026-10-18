import 'dart:async';

/// Every application-owned resource gets a release attempt, even after a failure.
Future<void> closeAppResources(
  Iterable<FutureOr<void> Function()> releases,
) async {
  final failures = <({Object error, StackTrace stack})>[];
  for (final release in releases) {
    try {
      await release();
    } catch (error, stack) {
      failures.add((error: error, stack: stack));
    }
  }

  if (failures.isNotEmpty) {
    Error.throwWithStackTrace(
      AppResourceCleanupFailure(
        failures.map((failure) => failure.error).toList(),
      ),
      failures.first.stack,
    );
  }
}

class AppResourceCleanupFailure implements Exception {
  AppResourceCleanupFailure(List<Object> causes)
    : causes = List.unmodifiable(causes);

  final List<Object> causes;

  @override
  String toString() =>
      'Application resource cleanup failed: ${causes.join('; ')}';
}

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits [true] when any network interface is available, [false] otherwise.
/// Starts with the current state, then streams changes.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  // Emit the initial connectivity state immediately
  final initial = await connectivity.checkConnectivity();
  yield _isOnline(initial);

  // Then yield every subsequent change
  yield* connectivity.onConnectivityChanged.map(_isOnline);
});

bool _isOnline(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

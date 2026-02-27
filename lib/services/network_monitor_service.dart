/// Monitors network connectivity and notifies when network becomes available.
/// Used by RemoteSessionManager to trigger immediate reconnection after outages.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'log_service.dart';

class NetworkMonitorService {
  static final NetworkMonitorService shared = NetworkMonitorService._();
  NetworkMonitorService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _wasConnected = true; // Assume connected initially
  Set<ConnectivityResult> _previousResults = {};

  /// Called when network transitions from unavailable to available,
  /// or when network route changes while staying connected (e.g., VPN toggle).
  void Function()? onNetworkBecameAvailable;

  /// Called when network becomes unavailable
  void Function()? onNetworkBecameUnavailable;

  /// Start monitoring network connectivity changes
  void startMonitoring() {
    // Check initial state
    _connectivity.checkConnectivity().then((results) {
      _wasConnected = _isConnected(results);
      _previousResults = results.toSet();
      hlog('Initial network state: ${_wasConnected ? "connected" : "disconnected"}',
          source: 'NetworkMonitor');
    });

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final isConnected = _isConnected(results);
      final currentResults = results.toSet();

      hlog('Network changed: $results (connected: $isConnected)', source: 'NetworkMonitor');

      // Detect transition from disconnected to connected
      if (!_wasConnected && isConnected) {
        hlog('Network became available', source: 'NetworkMonitor');
        onNetworkBecameAvailable?.call();
      }

      // Detect transition from connected to disconnected
      if (_wasConnected && !isConnected) {
        hlog('Network became unavailable', source: 'NetworkMonitor');
        onNetworkBecameUnavailable?.call();
      }

      // Detect route change while staying connected (e.g., VPN toggle).
      // Existing connections may be stale, so trigger disconnect + reconnect.
      if (_wasConnected && isConnected && !_setEquals(currentResults, _previousResults)) {
        hlog('Network route changed, triggering reconnect', source: 'NetworkMonitor');
        onNetworkBecameUnavailable?.call();
        onNetworkBecameAvailable?.call();
      }

      _wasConnected = isConnected;
      _previousResults = currentResults;
    });

    hlog('Started monitoring', source: 'NetworkMonitor');
  }

  /// Compare two sets for equality
  bool _setEquals(Set<ConnectivityResult> a, Set<ConnectivityResult> b) {
    return a.length == b.length && a.containsAll(b);
  }

  /// Stop monitoring network connectivity
  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
    hlog('Stopped monitoring', source: 'NetworkMonitor');
  }

  /// Check if any of the connectivity results indicate network access
  bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}

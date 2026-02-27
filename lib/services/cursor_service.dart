/// Cursor monitoring service for tracking system cursor changes.
/// Receives cursor updates from native code via method channel and
/// provides callback for sending cursor data via WebRTC data channel.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'log_service.dart';

/// Callback type for cursor change events
typedef CursorChangeCallback = void Function(Map<String, dynamic> cursorData);

/// Service for monitoring system cursor changes
class CursorService {
  // Singleton instance
  static final CursorService shared = CursorService._();

  CursorService._() {
    _setupMethodChannel();
  }

  // Method channel for native communication
  static const _channel = MethodChannel('app.afkdev.cursor_monitor');

  // Callback for cursor changes
  CursorChangeCallback? onCursorChanged;

  // Monitoring state
  bool _isMonitoring = false;
  bool get isMonitoring => _isMonitoring;

  /// Set up method channel handler for cursor updates from native code
  void _setupMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCursorChanged':
          _handleCursorChanged(call.arguments);
          break;
        default:
          hlog('Unknown method: ${call.method}', source: 'Cursor');
      }
    });
  }

  /// Handle cursor change event from native code
  void _handleCursorChanged(dynamic arguments) {
    if (arguments is! Map) {
      hlog('Invalid cursor data format', source: 'Cursor');
      return;
    }

    final cursorData = Map<String, dynamic>.from(arguments);
    onCursorChanged?.call(cursorData);
  }

  /// Start monitoring cursor changes
  Future<void> startMonitoring() async {
    if (_isMonitoring) {
      hlog('Already monitoring', source: 'Cursor');
      return;
    }

    // Only supported on macOS currently
    if (!Platform.isMacOS) {
      hlog('Cursor monitoring not supported on this platform', source: 'Cursor');
      return;
    }

    try {
      await _channel.invokeMethod('startMonitoring');
      _isMonitoring = true;
      hlog('Started cursor monitoring', source: 'Cursor');
    } catch (e) {
      hlog('Failed to start monitoring: $e', source: 'Cursor');
    }
  }

  /// Stop monitoring cursor changes
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) {
      return;
    }

    try {
      await _channel.invokeMethod('stopMonitoring');
      _isMonitoring = false;
      hlog('Stopped cursor monitoring', source: 'Cursor');
    } catch (e) {
      hlog('Failed to stop monitoring: $e', source: 'Cursor');
    }
  }

  /// Get current cursor data (one-shot, doesn't require monitoring)
  Future<Map<String, dynamic>?> getCurrentCursor() async {
    if (!Platform.isMacOS) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod('getCurrentCursor');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } catch (e) {
      hlog('Failed to get current cursor: $e', source: 'Cursor');
      return null;
    }
  }
}

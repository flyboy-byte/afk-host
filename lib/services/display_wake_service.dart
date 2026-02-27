/// Display wake service for macOS.
/// Wakes the display when a remote connection is initiated.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'log_service.dart';

class DisplayWakeService {
  DisplayWakeService._();
  static final shared = DisplayWakeService._();

  static const _channel = MethodChannel('app.afkdev.display_wake');

  /// Wake the display before starting screen capture.
  /// Returns true if successful, false otherwise.
  /// No-op on non-macOS platforms.
  Future<bool> wakeDisplay() async {
    if (!Platform.isMacOS) {
      return true; // No-op on other platforms
    }

    try {
      final result = await _channel.invokeMethod<bool>('wakeDisplay');
      hlog('Display wake result: $result', source: 'DisplayWakeService');
      return result ?? false;
    } catch (e) {
      hlog('Failed to wake display: $e', source: 'DisplayWakeService');
      return false;
    }
  }
}

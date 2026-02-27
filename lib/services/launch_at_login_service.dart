/// Service for managing app launch at login.
/// Uses SMAppService on macOS 13+ to register/unregister the app for automatic startup.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'log_service.dart';

class LaunchAtLoginService {
  LaunchAtLoginService._();
  static final shared = LaunchAtLoginService._();

  static const _channel = MethodChannel('app.afkdev.launch_at_login');

  /// Returns whether launch at login feature is supported on this OS version.
  /// Requires macOS 13.0+ for SMAppService.
  Future<bool> isSupported() async {
    if (!Platform.isMacOS) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } catch (e) {
      hlog('[LaunchAtLogin] Failed to check support: $e');
      return false;
    }
  }

  /// Returns whether launch at login is currently enabled.
  Future<bool> isEnabled() async {
    if (!Platform.isMacOS) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isEnabled');
      return result ?? false;
    } catch (e) {
      hlog('[LaunchAtLogin] Failed to check status: $e');
      return false;
    }
  }

  /// Enables or disables launch at login.
  /// Returns true if the operation succeeded.
  Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isMacOS) return false;

    try {
      final result = await _channel.invokeMethod<bool>('setEnabled', {
        'enabled': enabled,
      });
      hlog('[LaunchAtLogin] Set enabled=$enabled, success=${result ?? false}');
      return result ?? false;
    } catch (e) {
      hlog('[LaunchAtLogin] Failed to set enabled: $e');
      return false;
    }
  }
}

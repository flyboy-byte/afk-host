/// Permissions service for checking and requesting system permissions.
/// On macOS, handles Screen Recording and Accessibility permissions.
/// Other platforms return true (no explicit permissions needed).
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'log_service.dart';

/// Service for managing system permissions required by the app.
class PermissionsService {
  static const _channel = MethodChannel('app.afkdev.permissions');

  // Singleton instance
  static final PermissionsService shared = PermissionsService._();

  PermissionsService._();

  /// Check if screen recording permission is granted.
  Future<bool> checkScreenRecording() async {
    if (!Platform.isMacOS) return true;

    try {
      final result = await _channel.invokeMethod<bool>('checkScreenRecording');
      return result ?? false;
    } on PlatformException catch (e) {
      hlog('checkScreenRecording failed: ${e.message}', source: 'Permissions');
      return false;
    }
  }

  /// Request screen recording permission.
  /// On macOS, this prompts the system dialog or opens System Settings.
  Future<void> requestScreenRecording() async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod<void>('requestScreenRecording');
    } on PlatformException catch (e) {
      hlog('requestScreenRecording failed: ${e.message}', source: 'Permissions');
    }
  }

  /// Check if accessibility permission is granted.
  Future<bool> checkAccessibility() async {
    if (!Platform.isMacOS) return true;

    try {
      final result = await _channel.invokeMethod<bool>('checkAccessibility');
      return result ?? false;
    } on PlatformException catch (e) {
      hlog('checkAccessibility failed: ${e.message}', source: 'Permissions');
      return false;
    }
  }

  /// Request accessibility permission.
  /// On macOS, this prompts the system dialog.
  Future<void> requestAccessibility() async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod<void>('requestAccessibility');
    } on PlatformException catch (e) {
      hlog('requestAccessibility failed: ${e.message}', source: 'Permissions');
    }
  }

  /// Check all required permissions at once.
  /// Returns a map with 'screenRecording' and 'accessibility' boolean values.
  Future<Map<String, bool>> checkAll() async {
    if (!Platform.isMacOS) {
      return {'screenRecording': true, 'accessibility': true};
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkAll');
      if (result != null) {
        return {
          'screenRecording': result['screenRecording'] as bool? ?? false,
          'accessibility': result['accessibility'] as bool? ?? false,
        };
      }
    } on PlatformException catch (e) {
      hlog('checkAll failed: ${e.message}', source: 'Permissions');
    }

    return {'screenRecording': false, 'accessibility': false};
  }

  /// Check if all required permissions are granted.
  Future<bool> hasAllPermissions() async {
    final perms = await checkAll();
    return perms['screenRecording'] == true && perms['accessibility'] == true;
  }
}

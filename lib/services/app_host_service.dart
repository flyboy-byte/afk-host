/// App host service for communicating with the native macOS menu bar.
/// Receives commands from native (showPairing, showSettings) and sends
/// state updates (connection status, paired device count) to native.
library;

import 'dart:io';

import 'package:flutter/services.dart';

typedef VoidCallback = void Function();

/// Service for bridging between Flutter and native menu bar UI.
class AppHostService {
  static const _channel = MethodChannel('app.afkdev.app_host');

  static final AppHostService shared = AppHostService._();

  AppHostService._() {
    _setupMethodChannel();
  }

  VoidCallback? onShowPairing;
  VoidCallback? onShowSettings;
  VoidCallback? onQuit;

  void _setupMethodChannel() {
    if (!Platform.isMacOS) return;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'showPairing':
          onShowPairing?.call();
          break;
        case 'showSettings':
          onShowSettings?.call();
          break;
        case 'quit':
          onQuit?.call();
          break;
      }
    });
  }

  /// Update the native menu bar with current state
  Future<void> updateState({
    required bool isConnectedToServer,
    required bool isStreaming,
    required int connectedClientCount,
    required int pairedDeviceCount,
    List<String>? pairedDeviceNames,
    required String statusMessage,
    String? errorMessage,
  }) async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod('updateState', {
        'isConnectedToServer': isConnectedToServer,
        'isStreaming': isStreaming,
        'connectedClientCount': connectedClientCount,
        'pairedDeviceCount': pairedDeviceCount,
        'pairedDeviceNames': pairedDeviceNames ?? [],
        'statusMessage': statusMessage,
        'errorMessage': errorMessage ?? '',
      });
    } on PlatformException {
      // Native side may not be ready yet
    } on MissingPluginException {
      // Native plugin not registered yet
    }
  }

  /// Notify native that pairing completed successfully
  Future<void> notifyPairingComplete({required String deviceName}) async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod('notifyPairingComplete', {
        'deviceName': deviceName,
      });
    } on PlatformException {
      // Ignore
    } on MissingPluginException {
      // Ignore
    }
  }

  /// Show the main Flutter window (for onboarding)
  Future<void> showMainWindow() async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod('showMainWindow');
    } on PlatformException {
      // Ignore
    } on MissingPluginException {
      // Ignore
    }
  }

  /// Hide the main Flutter window
  Future<void> hideMainWindow() async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod('hideMainWindow');
    } on PlatformException {
      // Ignore
    } on MissingPluginException {
      // Ignore
    }
  }
}

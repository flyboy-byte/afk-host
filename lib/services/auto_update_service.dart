/// Service for managing automatic app updates.
/// Uses auto_updater package which wraps Sparkle (macOS) and WinSparkle (Windows).
library;

import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'log_service.dart';

class AutoUpdateService {
  AutoUpdateService._();
  static final shared = AutoUpdateService._();

  // Same appcast feed as the macOS Companion app
  static const String _feedUrl = 'https://afkdev.app/appcast.xml';

  // Check interval in seconds (default: 24 hours)
  static const int _checkIntervalSeconds = 86400;

  bool _initialized = false;

  /// Initialize the auto updater with the feed URL.
  /// Should be called once at app startup.
  Future<void> initialize() async {
    if (_initialized) return;
    if (!Platform.isMacOS && !Platform.isWindows) {
      hlog('[AutoUpdate] Platform not supported');
      return;
    }

    try {
      await autoUpdater.setFeedURL(_feedUrl);
      await autoUpdater.setScheduledCheckInterval(_checkIntervalSeconds);
      _initialized = true;
      hlog('[AutoUpdate] Initialized with feed: $_feedUrl');
    } catch (e) {
      hlog('[AutoUpdate] Failed to initialize: $e');
    }
  }

  /// Manually check for updates.
  /// This will show the Sparkle/WinSparkle update dialog if an update is available.
  Future<void> checkForUpdates() async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      hlog('[AutoUpdate] Platform not supported');
      return;
    }

    if (!_initialized) {
      await initialize();
    }

    try {
      hlog('[AutoUpdate] Checking for updates...');
      await autoUpdater.checkForUpdates();
    } catch (e) {
      hlog('[AutoUpdate] Failed to check for updates: $e');
    }
  }

  /// Returns whether auto-update is supported on the current platform.
  bool get isSupported => Platform.isMacOS || Platform.isWindows;
}

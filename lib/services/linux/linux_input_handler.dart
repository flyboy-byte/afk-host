/// Linux-specific input handler using xdg-desktop-portal.
/// This is used by InputService on Linux platforms.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import '../log_service.dart';
import 'remote_desktop_portal.dart';

/// Handles input injection on Linux via xdg-desktop-portal RemoteDesktop.
class LinuxInputHandler {
  // Singleton instance
  static final LinuxInputHandler shared = LinuxInputHandler._();

  LinuxInputHandler._();

  final RemoteDesktopPortal _portal = RemoteDesktopPortal.shared;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // Prevent concurrent initialization attempts
  bool _initializing = false;
  Completer<bool>? _initCompleter;
  
  // Track failed attempts to avoid hammering the portal
  int _failedAttempts = 0;
  DateTime? _lastAttempt;
  static const _maxFailedAttempts = 3;
  static const _retryDelay = Duration(seconds: 10);

  /// Initialize the Linux input handler
  /// This starts the RemoteDesktop portal session
  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }

    if (!Platform.isLinux) {
      hlog('LinuxInputHandler only works on Linux', source: 'LinuxInput');
      return false;
    }

    // Check if we've failed too many times recently
    if (_failedAttempts >= _maxFailedAttempts) {
      final now = DateTime.now();
      if (_lastAttempt != null && now.difference(_lastAttempt!) < _retryDelay) {
        hlog('Too many failed attempts, waiting before retry...', source: 'LinuxInput');
        return false;
      }
      // Reset after delay
      _failedAttempts = 0;
    }

    // If already initializing, wait for that to complete
    if (_initializing && _initCompleter != null) {
      hlog('Initialization already in progress, waiting...', source: 'LinuxInput');
      return await _initCompleter!.future;
    }

    _initializing = true;
    _initCompleter = Completer<bool>();
    _lastAttempt = DateTime.now();

    hlog('Initializing Linux input handler...', source: 'LinuxInput');

    try {
      final success = await _portal.startSession();
      if (success) {
        _initialized = true;
        _failedAttempts = 0;
        hlog('Linux input handler initialized', source: 'LinuxInput');
      } else {
        _failedAttempts++;
        hlog('Failed to initialize Linux input handler (attempt $_failedAttempts/$_maxFailedAttempts)', source: 'LinuxInput');
      }
      
      _initCompleter!.complete(success);
      return success;
    } catch (e) {
      _failedAttempts++;
      hlog('Exception during initialization: $e', source: 'LinuxInput');
      _initCompleter!.complete(false);
      return false;
    } finally {
      _initializing = false;
      _initCompleter = null;
    }
  }

  /// Set screen size for coordinate conversion
  void setScreenSize(Size size) {
    _portal.setScreenSize(size);
  }

  /// Move mouse to position (normalized 0-1 coordinates)
  Future<bool> mouseMove({required double x, required double y}) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return false;
    }

    return await _portal.notifyPointerMotionAbsolute(x, y);
  }

  /// Mouse button down
  Future<bool> mouseDown({
    required double x,
    required double y,
    required int button,
  }) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return false;
    }

    // First move to position
    await _portal.notifyPointerMotionAbsolute(x, y);

    // Then press button
    final linuxButton = LinuxButtonCode.fromIndex(button);
    return await _portal.notifyPointerButton(linuxButton, 1); // 1 = pressed
  }

  /// Mouse button up
  Future<bool> mouseUp({
    required double x,
    required double y,
    required int button,
  }) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return false;
    }

    // First move to position
    await _portal.notifyPointerMotionAbsolute(x, y);

    // Then release button
    final linuxButton = LinuxButtonCode.fromIndex(button);
    return await _portal.notifyPointerButton(linuxButton, 0); // 0 = released
  }

  /// Double-click at position
  Future<bool> doubleClick({required double x, required double y}) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return false;
    }

    // Move to position
    await _portal.notifyPointerMotionAbsolute(x, y);

    // Click twice
    final button = LinuxButtonCode.left;
    await _portal.notifyPointerButton(button, 1);
    await Future.delayed(const Duration(milliseconds: 10));
    await _portal.notifyPointerButton(button, 0);
    await Future.delayed(const Duration(milliseconds: 50));
    await _portal.notifyPointerButton(button, 1);
    await Future.delayed(const Duration(milliseconds: 10));
    return await _portal.notifyPointerButton(button, 0);
  }

  /// Scroll at position
  Future<bool> scroll({
    required double x,
    required double y,
    required double deltaX,
    required double deltaY,
  }) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return false;
    }

    // Move to position first
    await _portal.notifyPointerMotionAbsolute(x, y);

    // Send scroll event
    // Note: Portal expects axis values where positive = down/right
    return await _portal.notifyPointerAxis(deltaX, deltaY);
  }

  /// Key down using X11 keysym
  Future<bool> keyDown({required int keyCode}) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return false;
    }

    // The keyCode from client is X11 keysym
    return await _portal.notifyKeyboardKeysym(keyCode, 1); // 1 = pressed
  }

  /// Key up using X11 keysym
  Future<bool> keyUp({required int keyCode}) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return false;
    }

    return await _portal.notifyKeyboardKeysym(keyCode, 0); // 0 = released
  }

  /// Key press (down + up)
  Future<bool> keyPress({required int keyCode, String? character}) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return false;
    }

    // Press and release
    await _portal.notifyKeyboardKeysym(keyCode, 1);
    await Future.delayed(const Duration(milliseconds: 10));
    return await _portal.notifyKeyboardKeysym(keyCode, 0);
  }

  /// Paste text via clipboard
  /// On Linux, this types the text character by character using keysyms
  Future<bool> pasteText(String text) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return false;
    }

    // For now, we'll use a simple approach: type each character
    // A more robust approach would use the clipboard + Ctrl+V
    // but that requires additional portal access (org.freedesktop.portal.Clipboard)

    // TODO: Implement proper clipboard paste via portal
    // For now, simulate Ctrl+V assuming text is already in clipboard
    // This is a limitation - we'd need to set clipboard first

    hlog('pasteText: typing ${text.length} characters', source: 'LinuxInput');

    // Type Ctrl+V (keysym for 'v' is 0x76, Control_L is 0xffe3)
    // But this assumes clipboard is already set, which we can't do easily
    // For now, just return false to indicate not fully supported
    hlog('pasteText not fully implemented on Linux yet', source: 'LinuxInput');
    return false;
  }

  /// Cleanup
  Future<void> dispose() async {
    await _portal.dispose();
    _initialized = false;
    hlog('Linux input handler disposed', source: 'LinuxInput');
  }
}

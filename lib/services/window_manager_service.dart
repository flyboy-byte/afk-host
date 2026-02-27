/// Window manager service for discovering and manipulating windows.
/// Uses method channels to delegate to platform-specific implementations.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/window_info.dart';
import 'log_service.dart';

/// Window manager service that handles window discovery and manipulation.
class WindowManagerService {
  static const _channel = MethodChannel('app.afkdev.window_manager');

  // Singleton instance
  static final WindowManagerService shared = WindowManagerService._();

  WindowManagerService._();

  // Cached window list
  List<WindowInfo> _windows = [];
  String? _focusedWindowId;

  // Periodic discovery timer
  Timer? _discoveryTimer;

  // Callback for sending data channel messages to client
  void Function(Map<String, dynamic>)? sendDataChannelMessage;

  /// Get cached window list.
  List<WindowInfo> get windows => _windows;

  /// Get focused window ID.
  String? get focusedWindowId => _focusedWindowId;

  /// Start periodic window discovery.
  void startMonitoring() {
    if (!Platform.isMacOS && !Platform.isWindows) {
      hlog('Window management not supported on this platform', source: 'Window');
      return;
    }

    hlog('Starting window monitoring', source: 'Window');

    // Initial discovery
    _updateWindows();

    // Periodic discovery every 1 second
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateWindows();
    });
  }

  /// Stop window monitoring.
  void stopMonitoring() {
    hlog('Stopping window monitoring', source: 'Window');
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
  }

  /// Set the streaming display ID.
  /// This tells the native code which display is being captured so it can:
  /// 1. Move windows to the streaming display when focused
  /// 2. Report which windows are on the streaming display
  Future<void> setStreamingDisplayId(String? displayId) async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      return;
    }

    if (displayId == null) {
      hlog('Clearing streaming display ID', source: 'Window');
      return;
    }

    try {
      // Parse the source ID as an integer (it's the platform's native display ID)
      final displayIdInt = int.tryParse(displayId);
      if (displayIdInt == null) {
        hlog('Invalid display ID format: $displayId', source: 'Window');
        return;
      }

      await _channel.invokeMethod<void>('setStreamingDisplayId', {
        'displayId': displayIdInt,
      });
      hlog('Set streaming display ID: $displayId', source: 'Window');
    } on PlatformException catch (e) {
      hlog('setStreamingDisplayId failed: ${e.message}', source: 'Window');
    }
  }

  /// Broadcast current window list to connected client.
  void broadcastWindowList() {
    if (sendDataChannelMessage == null) {
      hlog('No data channel callback set', source: 'Window');
      return;
    }

    // If windows not discovered yet, trigger discovery first then broadcast
    if (_windows.isEmpty) {
      hlog('No windows cached, triggering discovery for new client', source: 'Window');
      _discoverAndBroadcast();
      return;
    }

    _sendWindowList();
  }

  /// Discover windows and broadcast (used when cache is empty).
  Future<void> _discoverAndBroadcast() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getWindows');
      if (result == null) return;

      final windowsList = result['windows'] as List<dynamic>? ?? [];
      final focusedId = result['focusedWindowId'] as String?;

      _windows = windowsList
          .map((w) => WindowInfo.fromMap(w as Map<dynamic, dynamic>))
          .toList();
      _focusedWindowId = focusedId;

      if (_windows.isEmpty) return;

      _sendWindowList();
    } on PlatformException catch (e) {
      hlog('Discovery failed: ${e.message}', source: 'Window');
    } catch (e) {
      hlog('Discovery failed: $e', source: 'Window');
    }
  }

  /// Send the current window list over data channel.
  void _sendWindowList() {
    if (sendDataChannelMessage == null) return;

    // Get focused window icon if available
    _getFocusedWindowIcon().then((iconData) {
      final message = {
        'type': 'window_list',
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
        'data': {
          'windows': _windows.map((w) => w.toMap()).toList(),
          if (_focusedWindowId != null) 'focusedWindowId': _focusedWindowId,
          if (iconData != null) 'focusedWindowIcon': iconData.base64Data,
        },
      };

      sendDataChannelMessage!(message);
    }).catchError((e) {
      // Send without icon on error
      final message = {
        'type': 'window_list',
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
        'data': {
          'windows': _windows.map((w) => w.toMap()).toList(),
          if (_focusedWindowId != null) 'focusedWindowId': _focusedWindowId,
        },
      };
      sendDataChannelMessage!(message);
    });
  }

  /// Process incoming data channel message.
  /// Returns true if the message was handled.
  Future<bool> processDataChannelMessage(String message) async {
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      final type = json['type'] as String?;
      final data = json['data'] as Map<String, dynamic>? ?? {};

      switch (type) {
        case 'window_focus':
          final windowId = data['windowId'] as String?;
          if (windowId == null) {
            hlog('window_focus missing windowId', source: 'Window');
            return false;
          }
          return await _handleWindowFocus(windowId);

        case 'window_fit':
          final windowId = data['windowId'] as String?;
          final visibleRegion = data['visibleRegion'] as Map<String, dynamic>?;
          if (windowId == null || visibleRegion == null) {
            hlog('window_fit missing required fields', source: 'Window');
            return false;
          }
          return await _handleWindowFit(windowId, visibleRegion);

        case 'icon_request':
          final hash = data['hash'] as String?;
          if (hash == null) {
            hlog('icon_request missing hash', source: 'Window');
            return false;
          }
          return await _handleIconRequest(hash);

        default:
          return false; // Not a window management message
      }
    } catch (e) {
      hlog('Failed to parse message: $e', source: 'Window');
      return false;
    }
  }

  // ============ Private Methods ============

  Future<void> _updateWindows() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getWindows');
      if (result == null) return;

      final windowsList = result['windows'] as List<dynamic>? ?? [];
      final focusedId = result['focusedWindowId'] as String?;

      final newWindows = windowsList
          .map((w) => WindowInfo.fromMap(w as Map<dynamic, dynamic>))
          .toList();

      // Check if windows changed
      final changed = _hasWindowsChanged(newWindows, focusedId);

      _windows = newWindows;
      _focusedWindowId = focusedId;

      if (changed) {
        broadcastWindowList();
      }
    } on PlatformException catch (e) {
      hlog('getWindows failed: ${e.message}', source: 'Window');
    }
  }

  bool _hasWindowsChanged(List<WindowInfo> newWindows, String? newFocusedId) {
    // Check focus change
    if (_focusedWindowId != newFocusedId) return true;

    // Check count change
    if (_windows.length != newWindows.length) return true;

    // Check window IDs
    final oldIds = _windows.map((w) => w.id).toSet();
    final newIds = newWindows.map((w) => w.id).toSet();
    if (oldIds.difference(newIds).isNotEmpty || newIds.difference(oldIds).isNotEmpty) {
      return true;
    }

    // Check title/bounds changes
    for (final newWindow in newWindows) {
      final oldWindow = _windows.firstWhere(
        (w) => w.id == newWindow.id,
        orElse: () => newWindow,
      );
      if (oldWindow.title != newWindow.title || oldWindow.bounds != newWindow.bounds) {
        return true;
      }
    }

    return false;
  }

  Future<bool> _handleWindowFocus(String windowId) async {
    hlog('Handling window focus request: $windowId', source: 'Window');

    try {
      final success = await _channel.invokeMethod<bool>('focusWindow', {
        'id': windowId,
      });

      // Send response to client
      if (sendDataChannelMessage != null) {
        final response = {
          'type': 'window_focus',
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
          'data': {
            'windowId': windowId,
            'success': success ?? false,
          },
        };
        sendDataChannelMessage!(response);
      }

      // Update state if successful
      if (success == true) {
        _focusedWindowId = windowId;
      }

      return success ?? false;
    } on PlatformException catch (e) {
      hlog('focusWindow failed: ${e.message}', source: 'Window');
      return false;
    }
  }

  Future<bool> _handleWindowFit(String windowId, Map<String, dynamic> visibleRegion) async {
    hlog('Handling window fit request: $windowId', source: 'Window');

    try {
      final success = await _channel.invokeMethod<bool>('setWindowBounds', {
        'id': windowId,
        'x': (visibleRegion['x'] as num).toDouble(),
        'y': (visibleRegion['y'] as num).toDouble(),
        'width': (visibleRegion['width'] as num).toDouble(),
        'height': (visibleRegion['height'] as num).toDouble(),
      });

      return success ?? false;
    } on PlatformException catch (e) {
      hlog('setWindowBounds failed: ${e.message}', source: 'Window');
      return false;
    }
  }

  Future<bool> _handleIconRequest(String hash) async {
    hlog('Handling icon request: $hash', source: 'Window');

    try {
      // Find window with this icon hash
      final window = _windows.firstWhere(
        (w) => w.iconHash == hash,
        orElse: () => _windows.first, // Fallback - shouldn't happen
      );

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getWindowIcon', {
        'id': window.id,
      });

      if (result != null && sendDataChannelMessage != null) {
        final response = {
          'type': 'icon_data',
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
          'data': {
            'hash': hash,
            'data': result['data'] as String?,
          },
        };
        sendDataChannelMessage!(response);
      }

      return result != null;
    } on PlatformException catch (e) {
      hlog('getWindowIcon failed: ${e.message}', source: 'Window');
      return false;
    }
  }

  Future<WindowIconData?> _getFocusedWindowIcon() async {
    if (_focusedWindowId == null) return null;

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getWindowIcon', {
        'id': _focusedWindowId,
      });

      if (result != null) {
        return WindowIconData.fromMap(result);
      }
    } on PlatformException catch (e) {
      hlog('getWindowIcon failed: ${e.message}', source: 'Window');
    }

    return null;
  }

  // ============ Direct Platform Methods ============

  /// Get all windows (direct call, bypasses cache).
  Future<List<WindowInfo>> getWindows() async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      return [];
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getWindows');
      if (result == null) return [];

      final windowsList = result['windows'] as List<dynamic>? ?? [];
      return windowsList
          .map((w) => WindowInfo.fromMap(w as Map<dynamic, dynamic>))
          .toList();
    } on PlatformException catch (e) {
      hlog('getWindows failed: ${e.message}', source: 'Window');
      return [];
    }
  }

  /// Focus a specific window.
  Future<bool> focusWindow(String windowId) async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('focusWindow', {
        'id': windowId,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      hlog('focusWindow failed: ${e.message}', source: 'Window');
      return false;
    }
  }

  /// Set window bounds (normalized 0-1 coordinates relative to screen).
  Future<bool> setWindowBounds({
    required String windowId,
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('setWindowBounds', {
        'id': windowId,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      hlog('setWindowBounds failed: ${e.message}', source: 'Window');
      return false;
    }
  }

  /// Get window icon data.
  Future<WindowIconData?> getWindowIcon(String windowId) async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getWindowIcon', {
        'id': windowId,
      });

      if (result != null) {
        return WindowIconData.fromMap(result);
      }
    } on PlatformException catch (e) {
      hlog('getWindowIcon failed: ${e.message}', source: 'Window');
    }

    return null;
  }

  /// Check accessibility permissions (macOS only).
  Future<bool> checkAccessibilityPermissions() async {
    if (!Platform.isMacOS) {
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>('checkAccessibility');
      return result ?? false;
    } on PlatformException catch (e) {
      hlog('checkAccessibility failed: ${e.message}', source: 'Window');
      return false;
    }
  }

  /// Request accessibility permissions (macOS only).
  Future<void> requestAccessibilityPermissions() async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod<void>('requestAccessibility');
    } on PlatformException catch (e) {
      hlog('requestAccessibility failed: ${e.message}', source: 'Window');
    }
  }
}

/// Unix socket server for communication with the `afk` CLI.
/// Listens on a namespaced socket under $TMPDIR/afk or $XDG_RUNTIME_DIR/afk
/// (namespace defaults to app bundle identifier; overridable via AFK_SOCKET_NAMESPACE).
/// Handles CLI commands like notifications, status checks, etc.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'log_service.dart';

/// Callback invoked when a notification is received from the CLI.
typedef NotificationCallback = void Function(String message, String timestamp);

/// Unix domain socket server for CLI communication.
class CliServer {
  static const String _source = 'CliServer';
  static const String _defaultSocketNamespace = 'app.afkdev.macos';

  ServerSocket? _server;
  String? _socketPath;

  /// Called when a `notify` message is received.
  NotificationCallback? onNotification;

  Future<String> _resolveSocketPath() async {
    final envNamespace = Platform.environment['AFK_SOCKET_NAMESPACE']?.trim();
    final namespace = (envNamespace != null && envNamespace.isNotEmpty)
        ? envNamespace
        : await _resolveBundleIdNamespace();

    // Linux: XDG_RUNTIME_DIR
    final xdgRuntime = Platform.environment['XDG_RUNTIME_DIR'];
    if (xdgRuntime != null && xdgRuntime.isNotEmpty) {
      return '$xdgRuntime/afk/$namespace.sock';
    }

    // macOS / fallback: TMPDIR
    final tmpDir = Platform.environment['TMPDIR'] ?? '/tmp';
    final clean = tmpDir.endsWith('/')
        ? tmpDir.substring(0, tmpDir.length - 1)
        : tmpDir;
    return '$clean/afk/$namespace.sock';
  }

  Future<String> _resolveBundleIdNamespace() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final packageName = packageInfo.packageName.trim();
      if (packageName.isNotEmpty) return packageName;
    } catch (_) {}
    return _defaultSocketNamespace;
  }

  /// Start listening on the Unix domain socket.
  Future<void> start() async {
    if (_server != null) {
      hlog('Already running', source: _source);
      return;
    }

    final path = await _resolveSocketPath();
    _socketPath = path;

    // Ensure parent directory exists
    final dir = Directory(path.substring(0, path.lastIndexOf('/')));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Remove stale socket file
    final socketFile = File(path);
    if (socketFile.existsSync()) {
      socketFile.deleteSync();
    }

    try {
      _server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      hlog('Listening on $path', source: _source);

      _server!.listen(
        _handleConnection,
        onError: (e) => hlog('Server error: $e', source: _source),
        onDone: () => hlog('Server closed', source: _source),
      );
    } catch (e) {
      hlog('Failed to start: $e', source: _source);
      rethrow;
    }
  }

  /// Stop the server and clean up the socket file.
  Future<void> stop() async {
    await _server?.close();
    _server = null;

    // Clean up socket file
    try {
      final path = _socketPath;
      if (path != null) {
        final socketFile = File(path);
        if (socketFile.existsSync()) {
          socketFile.deleteSync();
        }
      }
    } catch (_) {}

    _socketPath = null;
    hlog('Stopped', source: _source);
  }

  /// Whether the server is running.
  bool get isRunning => _server != null;

  void _handleConnection(Socket client) {
    final buffer = StringBuffer();

    client.listen(
      (data) {
        buffer.write(utf8.decode(data));

        // Process complete lines (newline-delimited JSON)
        final content = buffer.toString();
        final lines = content.split('\n');

        // Keep the last incomplete line in the buffer
        buffer.clear();
        if (!content.endsWith('\n')) {
          buffer.write(lines.removeLast());
        } else {
          lines.removeLast(); // Remove empty string after trailing newline
        }

        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          _handleMessage(line.trim());
        }
      },
      onError: (e) => hlog('Client error: $e', source: _source),
      onDone: () => client.close(),
    );
  }

  void _handleMessage(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'notify':
          final message = json['message'] as String? ?? '';
          final ts =
              json['ts'] as String? ?? DateTime.now().toUtc().toIso8601String();
          hlog('Notification: $message', source: _source);
          onNotification?.call(message, ts);

        case 'ping':
          // Status check from CLI — connection itself is the response
          break;

        default:
          hlog('Unknown message type: $type', source: _source);
      }
    } catch (e) {
      hlog('Failed to parse message: $e', source: _source);
    }
  }
}

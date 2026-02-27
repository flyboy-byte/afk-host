// LogService provides persistent logging for debugging.
// Logs are written to a file that users can copy and share for support.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class LogService {
  static final LogService shared = LogService._();

  static const int _maxFileSize = 1024 * 1024; // 1MB
  static const String _logFileName = 'afkhost.log';
  static const String _backupFileName = 'afkhost.log.1';

  File? _logFile;
  bool _initialized = false;

  LogService._();

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final appSupport = await getApplicationSupportDirectory();
      final logDir = Directory('${appSupport.path}/AFK Host');
      
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      
      _logFile = File('${logDir.path}/$_logFileName');
      _initialized = true;
    } catch (e) {
      // Silently fail - don't want logging to crash the app
    }
  }

  void log(String message, {String? source}) {
    final timestamp = DateTime.now().toIso8601String();
    final prefix = source != null ? '[$source] ' : '';
    final logLine = '$timestamp $prefix$message\n';

    // Also print to console for debugging
    stdout.writeln('$timestamp $prefix$message');

    // Write to file asynchronously
    _writeToFile(logLine);
  }

  Future<void> _writeToFile(String line) async {
    if (_logFile == null) return;

    try {
      await _rotateIfNeeded();

      if (await _logFile!.exists()) {
        await _logFile!.writeAsString(line, mode: FileMode.append);
      } else {
        await _logFile!.writeAsString(line);
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _rotateIfNeeded() async {
    if (_logFile == null) return;

    try {
      if (!await _logFile!.exists()) return;

      final stat = await _logFile!.stat();
      if (stat.size >= _maxFileSize) {
        final logDir = _logFile!.parent;
        final backupFile = File('${logDir.path}/$_backupFileName');

        // Delete old backup
        if (await backupFile.exists()) {
          await backupFile.delete();
        }

        // Move current to backup
        await _logFile!.rename(backupFile.path);
        _logFile = File('${logDir.path}/$_logFileName');
      }
    } catch (e) {
      // File doesn't exist yet, that's fine
    }
  }

  Future<String> getLogs() async {
    if (_logFile == null) return '(Log file not available)';

    var result = '';

    try {
      final logDir = _logFile!.parent;
      final backupFile = File('${logDir.path}/$_backupFileName');

      // Read backup first (older logs)
      if (await backupFile.exists()) {
        result += await backupFile.readAsString();
      }

      // Then current file (newer logs)
      if (await _logFile!.exists()) {
        result += await _logFile!.readAsString();
      }
    } catch (e) {
      return '(Error reading logs: $e)';
    }

    return result.isEmpty ? '(No logs)' : result;
  }

  Future<int> getLogSize() async {
    if (_logFile == null) return 0;

    var totalSize = 0;

    try {
      final logDir = _logFile!.parent;
      final backupFile = File('${logDir.path}/$_backupFileName');

      if (await backupFile.exists()) {
        totalSize += await backupFile.length();
      }

      if (await _logFile!.exists()) {
        totalSize += await _logFile!.length();
      }
    } catch (e) {
      return 0;
    }

    return totalSize;
  }

  Future<void> clearLogs() async {
    if (_logFile == null) return;

    try {
      final logDir = _logFile!.parent;
      final backupFile = File('${logDir.path}/$_backupFileName');

      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      if (await _logFile!.exists()) {
        await _logFile!.delete();
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<bool> copyToClipboard() async {
    final logs = await getLogs();
    await Clipboard.setData(ClipboardData(text: logs));
    return true;
  }
}

/// Global convenience function - drop-in replacement for print()
void hlog(String message, {String? source}) {
  LogService.shared.log(message, source: source);
}

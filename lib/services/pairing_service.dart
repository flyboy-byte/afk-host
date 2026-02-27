/// Pairing service for device pairing with mobile clients.
/// Handles the HTTP-based pairing protocol with the central server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'crypto_service.dart';
import 'device_storage.dart';
import 'log_service.dart';

/// Result of a successful pairing
class PairingResult {
  final String iosDeviceId;
  final String userId;
  final String userPublicKey;
  final String? deviceName;

  PairingResult({
    required this.iosDeviceId,
    required this.userId,
    required this.userPublicKey,
    this.deviceName,
  });

  factory PairingResult.fromJson(Map<String, dynamic> json) {
    return PairingResult(
      iosDeviceId: json['ios_device_id'] as String,
      userId: json['user_id'] as String,
      userPublicKey: json['user_public_key'] as String,
      deviceName: json['device_name'] as String?,
    );
  }
}

/// Pairing state
enum PairingState {
  idle,
  generating,
  waitingForClient,
  success,
  error,
  timeout,
}

class PairingService {
  PairingState _state = PairingState.idle;
  String? _currentCode;
  String? _errorMessage;
  PairingResult? _result;

  // For cancelling the long-poll
  http.Client? _httpClient;
  bool _cancelled = false;

  PairingState get state => _state;
  String? get currentCode => _currentCode;
  String? get errorMessage => _errorMessage;
  PairingResult? get result => _result;

  /// Generate a random 6-character pairing code (A-Z only)
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // Excludes I and O to avoid confusion
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Format code for display (ABC-DEF)
  String formatCodeForDisplay(String code) {
    if (code.length != 6) return code;
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  /// Start the pairing process
  /// Returns a stream of state updates
  Stream<PairingState> startPairing() async* {
    _cancelled = false;
    _state = PairingState.generating;
    _errorMessage = null;
    _result = null;
    yield _state;

    // Generate code
    _currentCode = _generateCode();
    hlog('Generated code: $_currentCode', source: 'Pairing');

    _state = PairingState.waitingForClient;
    yield _state;

    // Start long-poll to server
    try {
      final result = await _waitForPairing();

      if (_cancelled) {
        _state = PairingState.idle;
        yield _state;
        return;
      }

      if (result != null) {
        _result = result;
        _state = PairingState.success;

        // Store the paired client
        await DeviceStorage.shared.addPairedClient(PairedClient(
          deviceId: result.iosDeviceId,
          publicKey: result.userPublicKey,
          deviceName: result.deviceName,
        ));

        hlog('Pairing successful with ${result.deviceName ?? result.iosDeviceId}', source: 'Pairing');
        yield _state;
      } else {
        _state = PairingState.timeout;
        _errorMessage = 'No device paired within timeout';
        hlog('Pairing timed out for code: ${formatCodeForDisplay(_currentCode!)}', source: 'Pairing');
        yield _state;
      }
    } catch (e) {
      if (_cancelled) {
        _state = PairingState.idle;
        yield _state;
        return;
      }

      _state = PairingState.error;
      _errorMessage = e.toString();
      hlog('Pairing error: $e', source: 'Pairing');
      yield _state;
    }
  }

  /// Cancel the current pairing process
  void cancelPairing() {
    hlog('Cancelling pairing', source: 'Pairing');
    _cancelled = true;
    _httpClient?.close();
    _httpClient = null;
    _state = PairingState.idle;
    _currentCode = null;
  }

  /// Long-poll the server waiting for iOS to pair
  Future<PairingResult?> _waitForPairing() async {
    final code = _currentCode;
    if (code == null) return null;

    final serverUrl = DeviceStorage.shared.getServerUrl();
    final deviceId = DeviceStorage.shared.getOrCreateDeviceId();
    final publicKey = await CryptoService.shared.getPublicKeyBase64();
    final hostname = Platform.localHostname;

    // Build URL with query parameters
    // URL-encode the public key properly
    final encodedPubkey = Uri.encodeComponent(publicKey);
    final encodedName = Uri.encodeComponent(hostname);

    final url = Uri.parse(
      '$serverUrl/v0/pairing/$code?pubkey=$encodedPubkey&device_id=$deviceId&name=$encodedName'
    );

    _httpClient = http.Client();

    try {
      // Long-poll with 6 minute timeout (server has 5 min timeout)
      final response = await _httpClient!.get(url).timeout(
        const Duration(minutes: 6),
        onTimeout: () {
          throw TimeoutException('Pairing timeout');
        },
      );

      if (_cancelled) return null;

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return PairingResult.fromJson(json);
      } else if (response.statusCode == 408) {
        // Timeout from server
        return null;
      } else {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final error = json['error'] as Map<String, dynamic>?;
        throw Exception(error?['message'] ?? 'Pairing failed');
      }
    } on TimeoutException {
      return null;
    } finally {
      _httpClient?.close();
      _httpClient = null;
    }
  }

  /// Reset the service state
  void reset() {
    cancelPairing();
    _state = PairingState.idle;
    _currentCode = null;
    _errorMessage = null;
    _result = null;
  }
}

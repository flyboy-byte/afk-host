/// Device storage service for managing device identity and paired clients.
/// Handles device ID generation, Ed25519 keypair management, and server URL storage.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/paired_client.dart';
import 'log_service.dart';

export '../models/paired_client.dart';

class DeviceStorage {
  static final DeviceStorage shared = DeviceStorage._();
  DeviceStorage._();

  SharedPreferences? _prefs;
  String? _deviceId;
  Uint8List? _privateKey;

  // Keys for SharedPreferences
  static const _deviceIdKey = 'device_id';
  static const _privateKeyKey = 'private_key';
  static const _publicKeyKey = 'public_key';
  static const _serverUrlKey = 'server_url';
  static const _pairedClientsKey = 'paired_clients';
  static const _streamQualityKey = 'stream_quality'; // 1.0 = sharp, 2.0 = responsive
  static const _apnsTokensKey = 'apns_tokens'; // deviceId -> APNs token
  static const _lastConnectedClientKey = 'last_connected_client';
  static const _lastConnectedAtKey = 'last_connected_at'; // ISO-8601 timestamp

  // Default server URL
  static const _defaultServerUrl = 'https://connect.afkdev.app';

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get or create a unique device ID
  String getOrCreateDeviceId() {
    if (_deviceId != null) return _deviceId!;

    _deviceId = _prefs?.getString(_deviceIdKey);
    if (_deviceId == null) {
      // Generate a proper UUID
      _deviceId = const Uuid().v4();
      _prefs?.setString(_deviceIdKey, _deviceId!);
      hlog('Generated new device ID: $_deviceId', source: 'Storage');
    }
    return _deviceId!;
  }

  Uint8List? getPrivateKey() {
    if (_privateKey != null) return _privateKey;

    final stored = _prefs?.getString(_privateKeyKey);
    if (stored != null) {
      _privateKey = base64Decode(stored);
    }
    return _privateKey;
  }

  /// Store a new keypair (used when CryptoService generates keys)
  Future<void> storeKeyPair(Uint8List privateKey, String publicKeyBase64) async {
    _privateKey = privateKey;
    await _prefs?.setString(_privateKeyKey, base64Encode(privateKey));
    await _prefs?.setString(_publicKeyKey, publicKeyBase64);
    hlog('Stored new keypair', source: 'Storage');
  }

  /// Get server URL
  String getServerUrl() {
    return _prefs?.getString(_serverUrlKey) ?? _defaultServerUrl;
  }

  /// Set server URL
  Future<void> setServerUrl(String url) async {
    await _prefs?.setString(_serverUrlKey, url);
  }

  /// Check if there are any paired clients
  bool get hasPairedClients {
    final clients = _prefs?.getStringList(_pairedClientsKey);
    return clients != null && clients.isNotEmpty;
  }

  /// Get list of paired clients
  List<PairedClient> getPairedClients() {
    final clientsJson = _prefs?.getStringList(_pairedClientsKey) ?? [];
    return clientsJson.map((json) => PairedClient.fromJson(jsonDecode(json))).toList();
  }

  /// Add a paired client
  Future<void> addPairedClient(PairedClient client) async {
    final clients = getPairedClients();
    clients.removeWhere((c) => c.deviceId == client.deviceId);
    clients.add(client);

    final clientsJson = clients.map((c) => jsonEncode(c.toJson())).toList();
    await _prefs?.setStringList(_pairedClientsKey, clientsJson);
  }

  /// Get paired client by public key
  PairedClient? getPairedClient({String? byPublicKey, String? byDeviceId}) {
    final clients = getPairedClients();
    if (byPublicKey != null) {
      return clients.where((c) => c.publicKey == byPublicKey).firstOrNull;
    }
    if (byDeviceId != null) {
      return clients.where((c) => c.deviceId == byDeviceId).firstOrNull;
    }
    return null;
  }

  /// Remove all paired clients
  Future<void> clearPairedClients() async {
    await _prefs?.remove(_pairedClientsKey);
  }

  /// Get stream quality scale factor (1.0 = sharp/full res, 2.0 = responsive/half res)
  double getStreamQuality() {
    return _prefs?.getDouble(_streamQualityKey) ?? 1.0; // Default to sharp
  }

  /// Set stream quality scale factor
  Future<void> setStreamQuality(double scaleFactor) async {
    await _prefs?.setDouble(_streamQualityKey, scaleFactor);
    hlog('Stream quality set to: $scaleFactor', source: 'Storage');
  }

  /// Check if using responsive (lower resolution) streaming
  bool get isResponsiveStreaming => getStreamQuality() >= 2.0;

  // ── APNs Token Management ──

  /// Store APNs token for a paired client device.
  Future<void> storeApnsToken(String deviceId, String token) async {
    final tokens = _getApnsTokens();
    tokens[deviceId] = token;
    await _prefs?.setString(_apnsTokensKey, jsonEncode(tokens));
    hlog('Stored APNs token for device: $deviceId', source: 'Storage');
  }

  /// Get APNs token for a specific device.
  String? getApnsToken(String deviceId) {
    return _getApnsTokens()[deviceId];
  }

  /// Record which client connected most recently.
  Future<void> setLastConnectedClient(String deviceId) async {
    await _prefs?.setString(_lastConnectedClientKey, deviceId);
  }

  /// Get the last connected client's device ID.
  String? get lastConnectedClientId {
    return _prefs?.getString(_lastConnectedClientKey);
  }

  /// Record when a client was last connected.
  Future<void> setLastConnectedAt(DateTime at) async {
    await _prefs?.setString(_lastConnectedAtKey, at.toUtc().toIso8601String());
  }

  /// Timestamp of the last successful client connect.
  DateTime? get lastConnectedAt {
    final raw = _prefs?.getString(_lastConnectedAtKey);
    if (raw == null) return null;
    try {
      return DateTime.parse(raw).toUtc();
    } catch (_) {
      return null;
    }
  }

  /// Get APNs token for the last connected client.
  String? get lastConnectedApnsToken {
    final deviceId = lastConnectedClientId;
    if (deviceId == null) return null;
    return getApnsToken(deviceId);
  }

  Map<String, String> _getApnsTokens() {
    final raw = _prefs?.getString(_apnsTokensKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }
}

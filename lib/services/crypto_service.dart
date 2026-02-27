/// Cryptographic service for Ed25519 message signing and verification.
/// Handles secure communication with the signaling server and paired devices.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'log_service.dart';

class CryptoService {
  static final CryptoService shared = CryptoService._();
  CryptoService._();

  final _ed25519 = Ed25519();
  SimpleKeyPair? _keyPair;

  /// Initialize with existing keypair or generate new one
  Future<void> initialize({Uint8List? seed}) async {
    if (seed != null && seed.length >= 32) {
      // Create keypair from seed
      _keyPair = await _ed25519.newKeyPairFromSeed(seed.sublist(0, 32));
    } else {
      // Generate new random keypair
      _keyPair = await _ed25519.newKeyPair();
    }
  }

  /// Get public key as base64 string
  Future<String> getPublicKeyBase64() async {
    if (_keyPair == null) {
      await initialize();
    }
    final publicKey = await _keyPair!.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Get private key as bytes (for storage)
  Future<Uint8List> getPrivateKeyBytes() async {
    if (_keyPair == null) {
      await initialize();
    }
    final privateKey = await _keyPair!.extractPrivateKeyBytes();
    return Uint8List.fromList(privateKey);
  }

  /// Sign a message payload and return SignedPayload
  Future<SignedPayload?> signPayload(Map<String, dynamic> message) async {
    if (_keyPair == null) {
      await initialize();
    }

    try {
      // Serialize to canonical JSON (sorted keys for consistent signing)
      final payloadString = _canonicalJson(message);
      final payloadBytes = utf8.encode(payloadString);

      // Sign the payload
      final signature = await _ed25519.sign(payloadBytes, keyPair: _keyPair!);
      final signatureBase64 = base64Encode(signature.bytes);

      return SignedPayload(
        payload: payloadString,
        signature: signatureBase64,
      );
    } catch (e) {
      hlog('Failed to sign payload: $e', source: 'Crypto');
      return null;
    }
  }

  /// Verify a signed payload from a remote device
  Future<bool> verifyPayload(
    String payload,
    String signatureBase64,
    String publicKeyBase64,
  ) async {
    try {
      final payloadBytes = utf8.encode(payload);
      final signatureBytes = base64Decode(signatureBase64);
      final publicKeyBytes = base64Decode(publicKeyBase64);

      final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(signatureBytes, publicKey: publicKey);

      return await _ed25519.verify(payloadBytes, signature: signature);
    } catch (e) {
      hlog('Failed to verify payload: $e', source: 'Crypto');
      return false;
    }
  }

  /// Convert map to canonical JSON string (sorted keys)
  String _canonicalJson(Map<String, dynamic> map) {
    return jsonEncode(_sortedMap(map));
  }

  dynamic _sortedMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      final sorted = Map<String, dynamic>.fromEntries(
        value.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      return sorted.map((k, v) => MapEntry(k, _sortedMap(v)));
    } else if (value is List) {
      return value.map(_sortedMap).toList();
    }
    return value;
  }
}

/// Represents a signed payload for transmission
class SignedPayload {
  final String payload;
  final String signature;

  SignedPayload({required this.payload, required this.signature});
}

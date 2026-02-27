/// Model representing a paired client device.
library;

/// A client device that has been paired with this host.
class PairedClient {
  /// Unique identifier for the client device.
  final String deviceId;

  /// Client's Ed25519 public key (base64 encoded).
  final String publicKey;

  /// User-friendly name for the device.
  final String? deviceName;

  /// When the device was paired.
  final DateTime pairedAt;

  PairedClient({
    required this.deviceId,
    required this.publicKey,
    this.deviceName,
    DateTime? pairedAt,
  }) : pairedAt = pairedAt ?? DateTime.now();

  factory PairedClient.fromJson(Map<String, dynamic> json) {
    return PairedClient(
      deviceId: json['deviceId'] as String,
      publicKey: json['publicKey'] as String,
      deviceName: json['deviceName'] as String?,
      pairedAt: json['pairedAt'] != null
          ? DateTime.parse(json['pairedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'publicKey': publicKey,
        'deviceName': deviceName,
        'pairedAt': pairedAt.toIso8601String(),
      };
}

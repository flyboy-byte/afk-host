import 'package:flutter/services.dart';

class PipewireVideoCapture {
  static const MethodChannel _channel = MethodChannel('pipewire_video_capture');

  /// Start the PipeWire→V4L2 bridge.
  ///
  /// [fd] is the raw PipeWire fd obtained by calling OpenPipeWireRemote via
  /// the Dart D-Bus client (same connection that owns the portal session).
  /// [nodeId] is the PipeWire stream node from the portal Start response.
  ///
  /// Returns the V4L2 device path (e.g. "/dev/video0").
  /// Throws PlatformException with code "NO_V4L2" if v4l2loopback is not loaded.
  static Future<String> initialize({
    required int fd,
    required int nodeId,
    required int width,
    required int height,
  }) async {
    final result = await _channel.invokeMethod<String>('initialize', {
      'fd': fd,
      'nodeId': nodeId,
      'width': width,
      'height': height,
    });
    return result!;
  }

  static Future<void> dispose() async {
    await _channel.invokeMethod<void>('dispose');
  }
}

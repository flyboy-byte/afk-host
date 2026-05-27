import 'package:flutter/services.dart';

class PipewireVideoCapture {
  static const MethodChannel _channel = MethodChannel('pipewire_video_capture');

  /// Start the PipeWire→V4L2 bridge.
  ///
  /// [sessionHandle] is the D-Bus object path of the active ScreenCast portal
  /// session. The plugin calls OpenPipeWireRemote itself via GDBus so no fd
  /// needs to cross the Dart/C++ boundary. [nodeId] is the PipeWire stream node
  /// from the portal Start response.
  ///
  /// Returns the V4L2 device path (e.g. "/dev/video0") that libwebrtc captures
  /// from via getUserMedia.
  ///
  /// Throws PlatformException with code "NO_V4L2" if v4l2loopback is not loaded.
  static Future<String> initialize({
    required String sessionHandle,
    required int nodeId,
    required int width,
    required int height,
  }) async {
    final result = await _channel.invokeMethod<String>('initialize', {
      'sessionHandle': sessionHandle,
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

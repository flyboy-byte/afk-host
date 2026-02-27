/// Window information model for cross-platform window management.
library;

/// Represents a window on the host system.
class WindowInfo {
  /// Unique window identifier (CGWindowID on macOS, HWND on Windows).
  final String id;

  /// Window title.
  final String title;

  /// Application name that owns this window.
  final String appName;

  /// Window bounds normalized to 0-1 relative to the streaming display.
  final WindowBounds bounds;

  /// SHA256 hash of the app icon PNG data (for client-side caching).
  final String? iconHash;

  /// Whether this window is on the display currently being streamed.
  final bool isOnStreamingDisplay;

  const WindowInfo({
    required this.id,
    required this.title,
    required this.appName,
    required this.bounds,
    this.iconHash,
    this.isOnStreamingDisplay = true,
  });

  /// Create from platform channel map.
  factory WindowInfo.fromMap(Map<dynamic, dynamic> map) {
    return WindowInfo(
      id: map['id'] as String,
      title: map['title'] as String,
      appName: map['appName'] as String,
      bounds: WindowBounds.fromMap(map['bounds'] as Map<dynamic, dynamic>),
      iconHash: map['iconHash'] as String?,
      isOnStreamingDisplay: map['isOnStreamingDisplay'] as bool? ?? true,
    );
  }

  /// Convert to map for data channel serialization.
  /// [isWatched] is added by the caller based on watch state.
  Map<String, dynamic> toMap({bool isWatched = false}) {
    return {
      'id': id,
      'title': title,
      'appName': appName,
      'isOnStreamingDisplay': isOnStreamingDisplay,
      'bounds': bounds.toMap(),
      'isWatched': isWatched,
      if (iconHash != null) 'iconHash': iconHash,
    };
  }

  @override
  String toString() => 'WindowInfo(id: $id, title: $title, appName: $appName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          appName == other.appName &&
          bounds == other.bounds &&
          iconHash == other.iconHash;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      appName.hashCode ^
      bounds.hashCode ^
      iconHash.hashCode;
}

/// Window bounds normalized to 0-1 relative to the streaming display.
/// This allows the client to map bounds directly to video coordinates regardless
/// of Retina scaling or display resolution.
class WindowBounds {
  final double x;
  final double y;
  final double width;
  final double height;

  const WindowBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory WindowBounds.fromMap(Map<dynamic, dynamic> map) {
    return WindowBounds(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      width: (map['width'] as num).toDouble(),
      height: (map['height'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowBounds &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => x.hashCode ^ y.hashCode ^ width.hashCode ^ height.hashCode;
}

/// Icon data with hash for deduplication.
class WindowIconData {
  /// SHA256 hash of the icon PNG data.
  final String hash;

  /// Base64-encoded PNG data.
  final String base64Data;

  const WindowIconData({
    required this.hash,
    required this.base64Data,
  });

  factory WindowIconData.fromMap(Map<dynamic, dynamic> map) {
    return WindowIconData(
      hash: map['hash'] as String,
      base64Data: map['data'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hash': hash,
      'data': base64Data,
    };
  }
}

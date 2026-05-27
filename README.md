
<p align="center">
  <img src="https://afkdev.app/hero-image.webp" alt="AFK - Vibe coding from your couch" width="600">
</p>
<h1 align="center">
  <img src="assets/app_icon.png" alt="" width="28" style="vertical-align: middle;">
  AFK Host
</h1>

<p align="center">
  <strong>Remote desktop host for <a href="https://afkdev.app">AFK</a></strong><br>
  Stream your Mac, Windows, or Linux screen to your phone and control it with touch and voice.
</p>

<p align="center">
  <a href="https://afkdev.app">Website</a> •
  <a href="https://apps.apple.com/app/afk-remote/id6756719961">App Store</a> •
  <a href="https://play.google.com/store/apps/details?id=app.afkdev.afk">Google Play</a> •
  <a href="https://afkdev.app/download">Download</a>
</p>

---


## What is AFK?


AFK is a remote desktop app designed for **vibe coding** — directing AI agents like Claude Code from your phone using voice commands while lounging on your couch.

This repo contains the **host application** that runs on your computer and streams your screen to the AFK mobile app.

## Features

- 🖥️ **Low-latency Streaming** — WebRTC-powered screen sharing with adaptive quality
- 🎤 **Voice Control** — Speak commands to control your computer
- 🖱️ **Touch Input** — Full mouse and keyboard control from your phone
- 🪟 **Window Switcher** — Quickly switch between windows with touch
- 🔔 **CLI Notifications** — Get notified when Claude Code or Pi needs attention
- 🔒 **End-to-End Encryption** — Secure connection between devices

## Supported Platforms

| Platform | Status |
|----------|--------|
| macOS | ✅ Stable |
| Windows | 🚧 In development |
| Linux (Wayland/KDE) | 🧪 Experimental |

## Quick Start

1. **Download** the pre-built host app from [afkdev.app/download](https://afkdev.app/download)
2. **Install** and grant screen recording permission when prompted
3. **Get the mobile app** on [iOS](https://apps.apple.com/app/afk-remote/id6756719961) or [Android](https://play.google.com/store/apps/details?id=app.afkdev.afk)
4. **Pair** by entering the 6-digit code shown on your computer

For detailed setup instructions, visit [afkdev.app](https://afkdev.app).

## Build from Source

Requires [Flutter](https://flutter.dev/docs/get-started/install) 3.10+

```bash
# Clone the repo
git clone https://github.com/flyboy-byte/afk-host.git
cd afk-host

# Install dependencies
flutter pub get

# Run
flutter run -d macos    # macOS
flutter run -d windows  # Windows (rough edges)
flutter run -d linux    # Linux (Wayland — see notes below)

# Build release
flutter build macos
flutter build windows
flutter build linux
```

### Linux (Wayland)

Tested on KDE Plasma 6 with a Wayland session. Requirements:

- **PipeWire** — used for screen capture (libwebrtc falls back to PipeWire when `DISPLAY` is unset on Wayland)
- **xdg-desktop-portal** with a Wayland-capable backend (e.g. `xdg-desktop-portal-kde` or `xdg-desktop-portal-wlr`)
- **Node.js 22.6+** — required by the `afk` CLI (`--experimental-strip-types`); on Arch: `pacman -S nodejs-lts-krypton`

The app automatically unsets `DISPLAY` at startup on Wayland so libwebrtc uses PipeWire instead of XWayland (which would produce black frames). Mouse input uses `NotifyPointerMotionAbsolute` via `org.freedesktop.portal.RemoteDesktop` — the same portal ScreenCast session provides the stream node ID so tap-to-cursor accuracy is pixel-exact on single-monitor setups.

#### How absolute mouse positioning works

Getting `NotifyPointerMotionAbsolute` working on Wayland required a few non-obvious pieces:

**1. Single combined portal session**

The RemoteDesktop portal requires a stream node ID to anchor absolute coordinates. You get that node ID from a ScreenCast session — but both sessions must be created together in one `CreateSession` call (request types `RemoteDesktop | ScreenCast`). The stream node ID is returned in the `Start` response and passed as the third argument to `NotifyPointerMotionAbsolute`.

**2. `OpenPipeWireRemote` must run on the same D-Bus connection that owns the session**

If you call `OpenPipeWireRemote` from a different process or a new D-Bus connection you get `AccessDenied: Invalid session`. The call must go through the exact same connection object that created the session. In this app that means keeping the call in Dart (`dbus` package connection) rather than delegating it to the C++ PipeWire plugin.

**3. Extracting the PipeWire fd — Dart SDK workaround**

`OpenPipeWireRemote` returns a Unix fd as a `DBusUnixFd`. The obvious path is `ResourceHandle.toRawHandle()` but that method doesn't exist in Dart SDK 3.12.0. Workaround:

1. Snapshot `/proc/self/fd/` before the call.
2. Call `OpenPipeWireRemote`.
3. Snapshot again and diff — the new entry is the fd the kernel just handed us.
4. Call `dup()` via `dart:ffi` immediately so the Dart GC can't close the original before the C++ plugin reads it.

```dart
import 'dart:ffi' hide Size;  // 'hide Size' avoids conflict with dart:ui

final _dup = DynamicLibrary.open('libc.so.6')
    .lookupFunction<Int32 Function(Int32), int Function(int)>('dup');

Set<int> _scanOpenFds() {
  final fds = <int>{};
  for (final e in Directory('/proc/self/fd').listSync()) {
    final n = int.tryParse(e.path.split('/').last);
    if (n == null) continue;
    try { Link('/proc/self/fd/$n').targetSync(); fds.add(n); } catch (_) {}
  }
  return fds;
}
```

Each fd is validated with `Link('/proc/self/fd/$n').targetSync()` to skip entries whose underlying file was already closed (the directory fd from `listSync` itself closes and its number gets reused by `OpenPipeWireRemote`, which would otherwise appear as a false positive in the diff).

**4. C++ PipeWire plugin**

`pipewire_video_capture/` is a Flutter method-channel plugin written in C++ that receives the duped fd and node ID from Dart, connects to the PipeWire graph, and consumes frames from the portal stream. It was originally intended to bridge frames into a `v4l2loopback` device so libwebrtc could capture them via `getUserMedia` — that part was abandoned because libwebrtc's V4L2 capture path ignores `deviceId` on Linux and always falls back to `/dev/video0`. The plugin still runs and owns the PipeWire stream connection; video is captured separately via `getDisplayMedia`.

**Known limitations on Linux:**
- Window switcher not supported (no native plugin)
- Cursor sync not supported
- Multi-monitor absolute positioning untested (virtual display offset may shift cursor)
- Sessions may drop after ~1–2 minutes on LAN without a TURN server (ICE keepalive issue under investigation)

## Mobile App — Things to Investigate

The mobile app ([iOS](https://apps.apple.com/app/afk-remote/id6756719961) / [Android](https://play.google.com/store/apps/details?id=app.afkdev.afk)) is a separate closed-source repo. Open questions worth digging into:

- **TURN server / cellular connectivity** — LAN-only sessions work well; connecting over cellular likely fails ICE without a TURN relay. Look at adding Metered.ca or a self-hosted `coturn` instance to the mobile ICE config.
- **Session drop at ~72 seconds** — seen on both Linux and potentially mobile; investigate whether it's a libwebrtc PipeWire keepalive bug or an ICE consent refresh issue on the mobile side.
- **Paste text** — `LinuxInputHandler.pasteText()` is stubbed; mobile needs to send clipboard content and the host needs to synthesize it (portal `NotifyKeyboardKeysym` or type chars individually).
- **Multi-monitor source selection** — host currently captures the first ScreenCast source; mobile UI has no way to pick a monitor. Consider exposing source selection in the connection handshake.
- **Cursor image sync** — host knows the cursor shape (via portal cursor image API or polling); mobile renders a fixed crosshair. Streaming cursor bitmaps would improve feel.
- **Touch gesture mapping** — pinch/two-finger scroll handling on the mobile side; verify gesture deltas are scaled correctly for high-DPI hosts.

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  <a href="https://afkdev.app">afkdev.app</a>
</p>

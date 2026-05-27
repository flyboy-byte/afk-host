
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

# AFK Host Context Map

## What this repo is

`afk-host` is a Flutter desktop host application for the AFK mobile app.

Its job is to:

- stream the host screen to a paired mobile client over WebRTC
- receive remote input and inject it into the desktop OS
- expose window-switching metadata and cursor imagery
- pair the desktop host with a mobile device through AFK's server
- expose a local `afk` CLI bridge so coding agents can trigger phone notifications

This repo does **not** contain the mobile app or the backend signaling/pairing server.

## Main stack

- UI/runtime: Flutter desktop, Dart 3.10
- Media transport: `flutter_webrtc`
- Signaling transport: WebSocket via `web_socket_channel`
- Crypto/signatures: Ed25519 via `cryptography`
- Local persistence: `shared_preferences`
- Pairing HTTP calls: `http`
- Connectivity monitoring: `connectivity_plus`
- Auto-update: `auto_updater` (Sparkle on macOS, WinSparkle on Windows)
- CLI bridge: Node 24 + TypeScript executed natively, no build step
- Linux input path: D-Bus + `xdg-desktop-portal` RemoteDesktop

## Top-level layout

- `lib/`
  - Flutter app code: models, services, theme, views
- `cli/`
  - standalone `afk` command used by local coding agents
- `macos/Runner/`
  - native macOS menu bar shell and Flutter method-channel plugins
- `windows/runner/`
  - native Windows method-channel plugins for input/window management
- `linux/runner/`
  - standard Flutter Linux runner shell
- `assets/`
  - app icon and Windows CA certificate bundle

## Runtime entrypoints

- Flutter entry: `lib/main.dart`
- Node CLI entry: `cli/src/main.ts`
- macOS app shell: `macos/Runner/MainFlutterWindow.swift`
- Windows app shell: `windows/runner/flutter_window.cpp`

## Flutter architecture

### Boot flow

`lib/main.dart`:

1. initializes logging
2. adds a trusted CA bundle on Windows
3. creates and initializes `RemoteSessionManager`
4. initializes auto-update support
5. launches either onboarding or settings UI

### App shell

The Flutter UI is intentionally small and settings-oriented:

- `lib/ui/onboarding_view.dart`
  - 2-step onboarding: permissions, then pairing
- `lib/ui/settings_view.dart`
  - sections: General, CLI, Support, About
- `lib/theme/app_theme.dart`
  - dark macOS-like grouped settings appearance

This is not a fullscreen remote desktop UI. The actual remote desktop consumer is the AFK mobile app.

## Core service graph

### Session orchestration

`lib/services/remote_session_manager.dart` is the central coordinator.

It owns or coordinates:

- signaling connection lifecycle
- WebRTC peer connection and screen capture setup
- local Unix socket server for CLI notifications
- network reachability-triggered reconnects
- cursor monitoring
- window discovery + window-control messages
- remote input dispatch
- native app state updates for the macOS menu bar UI

### Signaling

`lib/services/signaling_service.dart`:

- connects to `${serverUrl}/v0/ws`
- registers the host device with device ID + public key
- relays peer-to-peer messages through a signed envelope
- handles `connect`, `disconnect`, `ping`, WebRTC answer, ICE, renegotiation
- reconnects with exponential backoff and jitter

The default server URL comes from storage and defaults to:

- `https://connect.afkdev.app`

### WebRTC

`lib/services/webrtc_service.dart`:

- creates the peer connection
- creates the `input` data channel
- captures the primary screen using `desktopCapturer` / `getDisplayMedia`
- pushes a video track into the peer connection
- applies bitrate and resolution scaling from the user's stream-quality setting
- prefers VP9, then H264, then other codecs

### Pairing

`lib/services/pairing_service.dart`:

- generates a 6-letter code
- long-polls `${serverUrl}/v0/pairing/<code>`
- sends host public key, host device ID, and hostname
- stores paired device metadata locally on success

### Local storage

`lib/services/device_storage.dart` stores:

- host device UUID
- Ed25519 private/public keypair
- signaling server URL override
- paired client list
- stream quality preference
- APNs tokens per client
- last connected client and timestamp

### Local CLI bridge

`lib/services/cli_server.dart` opens a Unix domain socket under:

- Linux: `$XDG_RUNTIME_DIR/afk/<namespace>.sock`
- macOS/fallback: `$TMPDIR/afk/<namespace>.sock`

The CLI can send:

- `notify`
- `ping`

Notifications are forwarded to the AFK server as push-notification requests if a recently active mobile client has an APNs token.

### Input injection

`lib/services/input_service.dart` parses incoming data-channel messages for:

- mouse move/button/double-click/scroll
- key up/down/press
- voice/clipboard paste
- legacy touch event shapes

Dispatch path by platform:

- macOS: method channel -> `InputInjection.swift`
- Windows: method channel -> `input_injection.cpp`
- Linux: `LinuxInputHandler` -> `RemoteDesktopPortal`

### Window management

`lib/services/window_manager_service.dart`:

- polls native window lists every second
- sends `window_list` messages to the mobile client
- focuses windows on request
- resizes/repositions windows to a requested visible region
- serves icon data on demand
- tracks which display is currently being streamed

### Cursor sync

`lib/services/cursor_service.dart`:

- starts/stops native cursor monitoring
- receives cursor-image updates
- forwards cursor images over the WebRTC data channel

### Permissions and host integration

Other supporting services:

- `permissions_service.dart`
  - screen recording + accessibility checks on macOS
- `app_host_service.dart`
  - macOS native menu bar bridge
- `launch_at_login_service.dart`
  - startup toggle
- `display_wake_service.dart`
  - wakes the display before capture
- `auto_update_service.dart`
  - appcast-based update checks
- `network_monitor_service.dart`
  - disconnect/reconnect behavior around route changes and outages
- `log_service.dart`
  - rotating local log file + clipboard export

## Native platform layers

### macOS

The macOS target is the most complete implementation.

Key files:

- `macos/Runner/MainFlutterWindow.swift`
  - hidden-by-default Flutter window
  - persistent menu bar item + popover
  - registers custom Flutter plugins
- `macos/Runner/AppState.swift`
  - native observable state for the menu bar UI
  - installs/removes `/usr/local/bin/afk`
- `macos/Runner/MenuBarView.swift`
  - native SwiftUI popover for quick status/actions
- `macos/Runner/PermissionsPlugin.swift`
  - screen-recording and accessibility permission handling
- `macos/Runner/InputInjection.swift`
  - CGEvent-based mouse/keyboard injection
- `macos/Runner/WindowManager.swift`
  - Accessibility API-based window enumeration/focus/move/resize/icon support
- `macos/Runner/CursorMonitor.swift`
  - polls cursor changes every 50ms and ships PNG cursor images

### Windows

Windows implements the core remote-control pieces but not the macOS menu bar shell.

Key files:

- `windows/runner/flutter_window.cpp`
  - runner window and plugin registration
- `windows/runner/input_injection.cpp`
  - `SendInput`-based mouse/keyboard injection
- `windows/runner/window_manager.cpp`
  - Win32 window enumeration, focus, icon extraction, display-aware movement

### Linux

Linux is partial and mostly focused on input injection:

- `lib/services/linux/linux_input_handler.dart`
  - lazy initialization wrapper
- `lib/services/linux/remote_desktop_portal.dart`
  - D-Bus session creation and event injection via `org.freedesktop.portal.RemoteDesktop`
- `linux/runner/*`
  - standard Flutter Linux runner scaffold

There is no Linux native window-manager plugin in this repo, so Linux does not have parity with macOS/Windows window discovery/control.

## CLI package

`cli/` is a separate Node-based local tool with no compile step.

Commands:

- `afk notify <message>`
- `afk setup [tool]`
- `afk status`

Important files:

- `cli/src/main.ts`
  - command dispatch
- `cli/src/socket.ts`
  - resolves socket namespace and writes newline-delimited JSON
- `cli/src/notify.ts`
  - silent best-effort notification send
- `cli/src/status.ts`
  - reports socket path and whether the host is listening
- `cli/src/setup.ts`
  - patches local agent configs for Claude Code and Pi Coding Agent

The CLI is designed to be non-blocking for agents: failed notifications do not error out the caller.

## Main protocol/data flows

### Pairing flow

1. Host generates 6-letter code
2. Host long-polls AFK server with its device ID, public key, and hostname
3. Mobile app completes pairing
4. Host stores paired client metadata locally

### Remote session flow

1. Host connects to signaling server over WebSocket
2. Mobile client sends signed `connect`
3. Host acknowledges and starts display wake + screen capture
4. Host creates WebRTC offer and relays it through signaling
5. Mobile returns answer + ICE
6. WebRTC data channel opens
7. Host starts window polling and cursor monitoring
8. Data channel carries input and window-control messages

### Agent notification flow

1. Local tool runs `afk notify "..."`
2. CLI writes JSON to the local Unix socket
3. Flutter host receives it in `CliServer`
4. `RemoteSessionManager` forwards it to the AFK backend as `push_notification`
5. Backend uses stored APNs token to notify the most recently active mobile device

## Important constraints and assumptions

- This host is designed around a single connected mobile client at a time.
- The streamed display is currently the first capture source returned by WebRTC.
- Window bounds are normalized to the active streaming display.
- macOS permission flow is a hard dependency for useful operation.
- Linux input paste is explicitly incomplete.
- There is no backend code here, so pairing/signaling behavior depends on AFK's external service contract.

## Fast mental model

If you need a short description of the architecture:

AFK Host is a Flutter desktop shell wrapped around a session coordinator. That coordinator keeps a signed WebSocket session to AFK's signaling service, spins up a WebRTC screen-sharing session to one mobile client, translates incoming control messages into native OS input/window operations, and exposes a local Unix socket so coding-agent CLIs can request push notifications to the user's phone.

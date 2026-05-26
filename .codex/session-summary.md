# AFK Host Session Summary

## Repo Snapshot

- Desktop host app built with Flutter/Dart
- Separate Node/TypeScript CLI in `cli/`
- Native integrations live under `macos/`, `windows/`, and `linux/`
- Main runtime entry is `lib/main.dart`
- Session orchestration centers on `lib/services/remote_session_manager.dart`

## Key Architecture

- Signaling: `lib/services/signaling_service.dart`
- WebRTC capture/stream: `lib/services/webrtc_service.dart`
- Input dispatch: `lib/services/input_service.dart`
- Linux input backend today: `lib/services/linux/linux_input_handler.dart` and `lib/services/linux/remote_desktop_portal.dart`
- Window management exists only for macOS and Windows
- Cursor image sync exists only for macOS

## Linux Port Status

- Do not treat Flutter Linux compilation as the main problem
- Real issues are capture behavior, input injection path, compositor restrictions, and maintainability
- Current repo already has partial Linux code, but Linux is not feature-complete
- README still marks Linux as planned

## Active Linux Decision

Phase 1 is intentionally narrow:

- X11-only Linux MVP
- No Wayland work yet
- No PipeWire/portal capture redesign yet
- No packaging or daemon work yet
- No broad Linux support refactor

## Current Phase 1 Capture Change

`lib/services/webrtc_service.dart` now hard-gates Linux capture to X11 sessions before calling:

- `desktopCapturer.getSources(...)`
- `navigator.mediaDevices.getDisplayMedia(...)`

This is the current proof step: verify whether existing `flutter_webrtc` `1.3.0` capture already works on Linux X11 before adding a native capture backend.

## Phase 1 Input Direction

Do not use Wayland injection paths for this phase.

Smallest X11-only input proof, if capture works:

- Prefer a temporary `xdotool` subprocess path first
- Do not jump to `ydotool` unless necessary
- Consider native XTest only after proving the behavior and deciding the subprocess path is too brittle

## Files Worth Reading First

- `AGENTS.md`
- `CONTEXT.md`
- `lib/services/webrtc_service.dart`
- `lib/services/input_service.dart`
- `lib/services/linux/linux_input_handler.dart`
- `lib/services/linux/remote_desktop_portal.dart`
- `linux/flutter/generated_plugin_registrant.cc`

## Known Commands

- Analyze: `flutter analyze`
- Run Linux app: `flutter run -d linux`
- X11-only check: `test "$XDG_SESSION_TYPE" = x11 && flutter run -d linux`

## Expected Success Signal

For the X11 capture proof:

- log line for screen source discovery
- log line `Screen capture started, track added to peer connection`
- mobile client receives live desktop video

## Known Unknowns

- Whether `flutter_webrtc 1.3.0` desktop capture works reliably on Linux X11 in this app
- Whether any Linux input path should remain subprocess-based or move to native XTest later
- Whether Linux v1 should exclude window switching and cursor-image sync

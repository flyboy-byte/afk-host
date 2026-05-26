# Repository Guidelines

## Project Structure & Module Organization

This repository contains a Flutter desktop host app plus a small Node-based CLI.

- `lib/`: main Dart application code
  - `services/`: signaling, WebRTC, storage, input, and platform integration
  - `services/linux/`: Linux-specific portal/input code
  - `models/`: lightweight data models
  - `ui/`: onboarding and settings views
  - `theme/`: shared app theme
- `cli/src/`: TypeScript sources for the `afk` command
- `assets/`: app icon and certificate assets
- `linux/`, `macos/`, `windows/`: platform runners and native integrations

## Build, Test, and Development Commands

- `flutter pub get`: install Dart and Flutter dependencies
- `flutter run -d macos`: run the macOS desktop app
- `flutter run -d windows`: run the Windows desktop app
- `flutter run -d linux`: run the Linux desktop app
- `flutter build macos` / `flutter build windows` / `flutter build linux`: build release binaries
- `flutter analyze`: run static analysis using `flutter_lints`
- `flutter test`: run Dart/Flutter tests if present
- `cd cli && npm run build`: placeholder script; currently documents that Node 24 runs the CLI TypeScript directly

## Coding Style & Naming Conventions

Use 2-space indentation in Dart and keep code consistent with existing Flutter style. Prefer:

- `PascalCase` for classes and widgets
- `camelCase` for methods, variables, and fields
- descriptive service names such as `RemoteSessionManager` and `WindowManagerService`

Follow `analysis_options.yaml`, which includes `package:flutter_lints/flutter.yaml`. Keep platform-specific logic isolated by OS rather than mixing behavior into shared services.

## Testing Guidelines

There is no top-level `test/` suite in this checkout yet, so keep changes small and verify with targeted manual runs plus `flutter analyze`. If you add Dart tests, place them under `test/` and name files `*_test.dart`. Do not add broad test scaffolding unless the change clearly benefits from it.

## Commit & Pull Request Guidelines

Recent commits are short, imperative, and direct, for example:

- `Update README.md`
- `Initial release: AFK Host v1.5.3`

Use concise subject lines that describe the user-visible change. For pull requests, include:

- a clear summary of behavior changed
- affected platforms (`macOS`, `Windows`, `Linux`)
- manual verification steps
- screenshots or logs for UI/platform-specific work when relevant

## Platform Notes

Treat Linux, X11, and Wayland as separate tracks. Do not assume cross-platform parity for capture, input, or native integrations without verifying the exact code path in this repository first.

## Resume Notes

When resuming work on this repository, read these files first:

- `CONTEXT.md`: architecture and folder map
- `.codex/session-summary.md`: current project state and active technical decisions

Current high-priority thread: Linux Phase 1 is an `X11-only` proof of concept. Keep capture, input, and Wayland concerns separate, and do not broaden scope without verifying the existing code path first.

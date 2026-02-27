# Changelog

All notable changes to AFK Host (macOS/Windows/Linux host app) will be documented in this file.

Note: Versions 1.0.0–1.3.3 were the native macOS Companion (Swift). Starting with 1.4.0, the host is rebuilt in Flutter for cross-platform support.

## [Unreleased]

Migrated from native Swift to Flutter for cross-platform support. Feature parity with 1.3.3, plus:

### Added
- **Windows support** - Window management and input injection (experimental)
- **Linux support** - Input injection via xdg-desktop-portal (experimental)
- **Permissions onboarding** - Guided setup for Screen Recording and Accessibility permissions on first launch

### Fixed
- Slow reconnection on app resume (background/foreground, lock/unlock)
- Session state machine getting stuck on reconnect
- Crash from concurrent screen capture calls

## [1.3.3] - 2026-01-28

### Fixed
- Auto-reconnect regression where iOS client got stuck in reconnecting state after screen unlock

## [1.3.2] - 2026-01-22

### Added
- Crash reporting for better diagnostics

## [1.3.1] - 2026-01-22

### Fixed
- WebSocket reconnection stability - connections no longer get stuck after network changes
- Crash when switching windows rapidly

### Added
- Network monitoring for faster reconnection when connectivity returns

## [1.3.0] - 2026-01-16

### Added
- Custom menu bar icon

### Fixed
- Connection bugs

## [1.2.0] - 2026-01-09

### Added
- **Diagnostic Logging** - Copy logs from Settings > Support for troubleshooting
- **Check for Updates** - Manual update check in Settings
- **Improved Installer** - Nicer DMG with drag-to-Applications

### Changed
- **Easier Pairing** - Letters-only codes are clearer to read/type

## [1.1.0] - 2025-12-24

### Added
- **Multi-device pairing** - Pair multiple iOS devices with your Mac
- Settings now shows paired devices with individual remove buttons

### Fixed
- Window resizing for "Fit to Call" on some apps

## [1.0.0] - 2025-12-22

Initial release.

### Added
- Auto-update support - check for updates from the menu
- Improved onboarding with step-by-step pairing instructions
- macOS app menu (About, Settings, Quit)
- Re-pair device button in Settings

### Fixed
- Intermittent voice input paste failures

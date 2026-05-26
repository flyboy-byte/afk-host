# AFK Host TODO

## Current Focus

Phase 1 Linux proof of concept: X11-only capture validation.

## Next Actions

- Run from a real X11 session:
  - `test "$XDG_SESSION_TYPE" = x11 && flutter run -d linux`
- Confirm whether existing `flutter_webrtc` capture works with:
  - source discovery
  - `getDisplayMedia`
  - non-empty video track
  - visible video on the mobile client

## If Capture Works

- Add the smallest X11-only input proof
- Prefer a temporary `xdotool` subprocess path first
- Do not start Wayland work

## If Capture Fails

- Record the exact failing step:
  - no sources
  - `getDisplayMedia` error
  - empty track
  - black/frozen frames
- Then decide whether a Linux native X11 capture plugin spike is necessary

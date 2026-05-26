# Wayland Testing Plan for AFK Host Linux Support

## Current Status Summary

### Environment
- **Session Type**: Wayland (KDE)
- **Desktop**: KDE Plasma
- **flutter_webrtc**: 1.3.0
- **D-Bus library**: 0.7.10 (already in dependencies)
- **Flutter**: Not currently in PATH (needs setup)

### Existing Implementation
The codebase already has Linux portal-based input:
- `lib/services/linux/linux_input_handler.dart` - Input wrapper
- `lib/services/linux/remote_desktop_portal.dart` - D-Bus RemoteDesktop portal
- Input injection uses `org.freedesktop.portal.RemoteDesktop` (works on Wayland)

### Known Issue
**flutter_webrtc Issue #1542**: `desktopCapturer.getSources()` crashes on PipeWire/Wayland
- PipeWire shows a system dialog for screen selection
- flutter_webrtc doesn't wait for the dialog response
- This is the standard capture mechanism on modern Linux (Fedora, Arch, Ubuntu 22.04+)
- Issue is still OPEN as of March 2024

## Testing Strategy

### Phase 1: Determine Capture Viability

#### Prerequisites
1. Install/setup Flutter in PATH
2. Run `flutter pub get` to fetch dependencies
3. Ensure system has required libraries:
   - `libwebrtc` (should come with flutter_webrtc)
   - PipeWire (should already be running on Wayland)
   - xdg-desktop-portal (for portal dialogs)

#### Test 1: Basic Build Test
```bash
flutter analyze
flutter build linux --debug
```
**Expected**: Clean build with no errors
**Purpose**: Verify the app compiles on Linux

#### Test 2: Capture Attempt with Logging
Run the app and attempt to connect from mobile client. Watch logs for:
- Whether `desktopCapturer.getSources()` returns any sources
- Whether it crashes or hangs
- Whether PipeWire portal dialog appears
- What `getDisplayMedia()` does

**Add these diagnostic logs**:
- Log before calling `desktopCapturer.getSources()`
- Log the number of sources returned
- Log each source name and ID
- Log before calling `getDisplayMedia()`
- Log any exceptions during capture

#### Test 3: Alternative Capture Approach
If `desktopCapturer.getSources()` fails, try calling `getDisplayMedia()` **directly** without pre-enumerating sources:
```dart
_localStream = await navigator.mediaDevices.getDisplayMedia({
  'video': {
    'mandatory': {
      'minWidth': 1920,
      'minHeight': 1080,
      'frameRate': 30.0,
    },
  },
  'audio': false,
});
```
This might trigger the PipeWire portal dialog correctly.

### Phase 2: Input Testing

Once/if capture works:

#### Test 4: Portal Input Initialization
- Test if `RemoteDesktopPortal.startSession()` completes successfully
- Check if permission dialog appears
- Verify input events are sent without errors

#### Test 5: Basic Input Operations
- Mouse move
- Mouse click
- Keyboard input
- Scroll

### Phase 3: Fallback Strategy

If flutter_webrtc capture doesn't work on Wayland:

#### Option A: Wait for flutter_webrtc fix
- File/track issue #1542
- Use X11 fallback temporarily with clear error messages

#### Option B: Native PipeWire capture
- Implement direct PipeWire screen capture via D-Bus portal
- Use `org.freedesktop.portal.ScreenCast`
- Feed frames into WebRTC manually
- **Complex**: Requires significant native code

#### Option C: X11-only with proper messaging
- Add back the session check
- Show user-friendly error on Wayland: "Wayland support coming soon. Please use X11 session for now."
- Update README to document limitation

## Immediate Next Steps

1. **Install Flutter** (if not present)
   ```bash
   # Option 1: Snap
   sudo snap install flutter --classic

   # Option 2: Direct download
   git clone https://github.com/flutter/flutter.git -b stable ~/flutter
   export PATH="$PATH:$HOME/flutter/bin"
   ```

2. **Add diagnostic logging** to `lib/services/webrtc_service.dart`:
   - More verbose capture flow logging
   - Log all exceptions with stack traces

3. **Test run**:
   ```bash
   flutter run -d linux
   ```
   - Observe console output during capture attempt
   - Note any portal dialogs that appear
   - Test with mobile client connection

4. **Document results**:
   - Does capture work?
   - What errors occur?
   - Does PipeWire dialog appear?
   - Which approach works (pre-enumerate vs direct getDisplayMedia)?

## Success Criteria

**Minimal Success**:
- App builds and runs on Linux
- Screen capture works on Wayland OR clear error message explaining limitation
- Input injection works via portals

**Full Success**:
- Screen capture works on Wayland with PipeWire
- Input injection works
- User experience is comparable to macOS/Windows

## Risk Assessment

**High Risk**: flutter_webrtc 1.3.0 may not support PipeWire capture at all
- Mitigation: Test quickly to determine viability
- If blocked: Document limitation and use X11 fallback with proper UX

**Medium Risk**: Portal permissions may be confusing for users
- Mitigation: Add clear documentation and error messages

**Low Risk**: Build issues
- Mitigation: Standard Flutter Linux dependencies should handle this

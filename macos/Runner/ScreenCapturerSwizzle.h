//
//  ScreenCapturerSwizzle.h
//  Runner
//
//  Swizzles flutter_webrtc's getDisplayMedia to use ScreenCaptureKit with
//  showsCursor = NO. This hides the system cursor from screen capture,
//  allowing the client to render its own virtual cursor.
//
//  The swizzle auto-installs on app launch via __attribute__((constructor)).
//  Manual installation is available via InstallScreenCapturerSwizzle() if needed.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs the screen capturer swizzle if not already installed.
/// Called automatically on app launch; manual call is optional.
void InstallScreenCapturerSwizzle(void);

NS_ASSUME_NONNULL_END

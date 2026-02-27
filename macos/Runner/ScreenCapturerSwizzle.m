//
//  ScreenCapturerSwizzle.m
//  Runner
//
//  Swizzles flutter_webrtc's getDisplayMedia to use ScreenCaptureKit with
//  showsCursor = NO. This hides the system cursor from screen capture,
//  allowing the client to render its own virtual cursor.
//
//  This is a minimal runtime patch that doesn't require forking flutter_webrtc.
//

#import "ScreenCapturerSwizzle.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <WebRTC/WebRTC.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

#pragma mark - SCKCursorHiddenCapturer

/// ScreenCaptureKit-based video capturer that hides the system cursor.
API_AVAILABLE(macos(12.3))
@interface SCKCursorHiddenCapturer : RTCVideoCapturer <SCStreamDelegate, SCStreamOutput>
- (instancetype)initWithDelegate:(id<RTCVideoCapturerDelegate>)delegate;
- (void)startCaptureWithFPS:(NSInteger)fps;
- (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler;
@end

API_AVAILABLE(macos(12.3))
@implementation SCKCursorHiddenCapturer {
    SCStream *_stream;
    BOOL _isCapturing;
    __weak id<RTCVideoCapturerDelegate> _captureDelegate;
}

- (instancetype)initWithDelegate:(id<RTCVideoCapturerDelegate>)delegate {
    self = [super initWithDelegate:delegate];
    if (self) {
        _captureDelegate = delegate;
        _isCapturing = NO;
    }
    return self;
}

- (void)startCaptureWithFPS:(NSInteger)fps {
    if (_isCapturing) return;
    
    // Wake display if sleeping
    IOPMAssertionID assertionID = 0;
    IOPMAssertionDeclareUserActivity(CFSTR("Screen capture"), kIOPMUserActiveLocal, &assertionID);
    
    // Small delay to ensure display is ready after wake
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), 
                   dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self startCaptureAsyncWithFPS:fps];
    });
}

- (void)startCaptureAsyncWithFPS:(NSInteger)fps {
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO
                                              onScreenWindowsOnly:YES
                                                completionHandler:^(SCShareableContent *content, NSError *error) {
        if (error || content.displays.count == 0) {
            NSLog(@"[SCKCursorHiddenCapturer] Failed to get displays: %@", error);
            return;
        }
        
        SCDisplay *display = content.displays.firstObject;
        
        SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
        config.minimumFrameInterval = CMTimeMake(1, (int32_t)fps);
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
        config.scalesToFit = YES;
        config.showsCursor = NO;  // Hide system cursor
        
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display
                                                     excludingApplications:@[]
                                                          exceptingWindows:@[]];
        
        // Determine display scale for proper resolution
        CGFloat scale = NSScreen.mainScreen.backingScaleFactor;
        if (@available(macOS 14.0, *)) {
            scale = filter.pointPixelScale;
        }
        config.width = (size_t)(display.width * scale);
        config.height = (size_t)(display.height * scale);
        
        self->_stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
        
        NSError *addError;
        [self->_stream addStreamOutput:self
                                  type:SCStreamOutputTypeScreen
                     sampleHandlerQueue:dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0)
                                  error:&addError];
        
        if (addError) {
            NSLog(@"[SCKCursorHiddenCapturer] Failed to add stream output: %@", addError);
            return;
        }
        
        [self->_stream startCaptureWithCompletionHandler:^(NSError *startError) {
            if (startError) {
                NSLog(@"[SCKCursorHiddenCapturer] Failed to start capture: %@", startError);
            } else {
                self->_isCapturing = YES;
            }
        }];
    }];
}

- (void)stopCaptureWithCompletionHandler:(void (^)(void))handler {
    SCStream *stream = _stream;
    _stream = nil;
    _isCapturing = NO;
    
    if (stream) {
        [stream stopCaptureWithCompletionHandler:^(NSError *error) {
            if (handler) handler();
        }];
    } else if (handler) {
        handler();
    }
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    NSLog(@"[SCKCursorHiddenCapturer] Stream stopped with error: %@", error);
    _isCapturing = NO;
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeScreen) return;
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return;
    
    int64_t timeStampNs = (int64_t)(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1e9);
    RTCCVPixelBuffer *rtcBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:imageBuffer];
    RTCVideoFrame *frame = [[RTCVideoFrame alloc] initWithBuffer:rtcBuffer
                                                        rotation:RTCVideoRotation_0
                                                     timeStampNs:timeStampNs];
    [_captureDelegate capturer:self didCaptureVideoFrame:frame];
}

@end

#pragma mark - Method Swizzling

static IMP _originalGetDisplayMedia = NULL;

/// Creates a cursor-hidden screen capture using ScreenCaptureKit.
static void getDisplayMediaWithCursorHidden(id self, NSDictionary *constraints, void (^result)(id)) {
    if (@available(macOS 12.3, *)) {
        RTCPeerConnectionFactory *factory = [self valueForKey:@"peerConnectionFactory"];
        if (!factory) {
            // Fall back to original if factory not available
            ((void (*)(id, SEL, NSDictionary*, void(^)(id)))_originalGetDisplayMedia)(
                self, sel_registerName("getDisplayMedia:result:"), constraints, result);
            return;
        }
        
        NSString *mediaStreamId = [[NSUUID UUID] UUIDString];
        RTCMediaStream *mediaStream = [factory mediaStreamWithStreamId:mediaStreamId];
        RTCVideoSource *videoSource = [factory videoSourceForScreenCast:YES];
        NSString *trackUUID = [[NSUUID UUID] UUIDString];
        
        // Parse FPS from constraints (default 30)
        NSInteger fps = 30;
        id videoConstraints = constraints[@"video"];
        if ([videoConstraints isKindOfClass:[NSDictionary class]]) {
            id mandatory = videoConstraints[@"mandatory"];
            if ([mandatory isKindOfClass:[NSDictionary class]]) {
                id frameRate = mandatory[@"frameRate"];
                if ([frameRate isKindOfClass:[NSNumber class]]) {
                    fps = [frameRate integerValue];
                }
            }
        }
        
        // Create cursor-hidden capturer
        SCKCursorHiddenCapturer *capturer = [[SCKCursorHiddenCapturer alloc] initWithDelegate:videoSource];
        [capturer startCaptureWithFPS:fps];
        
        // Store stop handler for cleanup
        NSMutableDictionary *stopHandlers = [self valueForKey:@"videoCapturerStopHandlers"];
        if (stopHandlers) {
            stopHandlers[trackUUID] = ^(void (^handler)(void)) {
                [capturer stopCaptureWithCompletionHandler:handler];
            };
        }
        
        // Create and configure video track
        RTCVideoTrack *videoTrack = [factory videoTrackWithSource:videoSource trackId:trackUUID];
        [mediaStream addVideoTrack:videoTrack];
        
        // Store local stream
        NSMutableDictionary *localStreams = [self valueForKey:@"localStreams"];
        if (localStreams) {
            localStreams[mediaStreamId] = mediaStream;
        }
        
        // Store local track with LocalVideoTrack wrapper (required by flutter_webrtc)
        NSMutableDictionary *localTracks = [self valueForKey:@"localTracks"];
        if (localTracks) {
            Class LocalVideoTrackClass = NSClassFromString(@"LocalVideoTrack");
            if (LocalVideoTrackClass) {
                id (*initWithTrackIMP)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
                id localVideoTrack = initWithTrackIMP([LocalVideoTrackClass alloc], 
                                                       sel_registerName("initWithTrack:"), 
                                                       videoTrack);
                if (localVideoTrack) {
                    localTracks[trackUUID] = localVideoTrack;
                }
            }
        }
        
        // Build result matching flutter_webrtc's expected format
        NSMutableArray *videoTracks = [NSMutableArray array];
        for (RTCVideoTrack *track in mediaStream.videoTracks) {
            [videoTracks addObject:@{
                @"id": track.trackId,
                @"kind": track.kind,
                @"label": track.trackId,
                @"enabled": @(track.isEnabled),
                @"remote": @(YES),
                @"readyState": @"live"
            }];
        }
        
        result(@{
            @"streamId": mediaStreamId,
            @"audioTracks": @[],
            @"videoTracks": videoTracks
        });
    }
}

/// Swizzled replacement for getDisplayMedia:result: that uses cursor-hidden capture.
static void swizzled_getDisplayMedia(id self, SEL _cmd, NSDictionary *constraints, void (^result)(id)) {
    // Use ScreenCaptureKit with cursor hidden on macOS 12.3+
    if (@available(macOS 12.3, *)) {
        getDisplayMediaWithCursorHidden(self, constraints, result);
        return;
    }
    
    // Fall back to original for older macOS
    ((void (*)(id, SEL, NSDictionary*, void(^)(id)))_originalGetDisplayMedia)(self, _cmd, constraints, result);
}

#pragma mark - Installation

void InstallScreenCapturerSwizzle(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class pluginClass = NSClassFromString(@"FlutterWebRTCPlugin");
        if (!pluginClass) {
            // Plugin not loaded yet, retry after delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), 
                          dispatch_get_main_queue(), ^{
                InstallScreenCapturerSwizzle();
            });
            return;
        }
        
        SEL originalSelector = sel_registerName("getDisplayMedia:result:");
        Method originalMethod = class_getInstanceMethod(pluginClass, originalSelector);
        
        if (!originalMethod) {
            NSLog(@"[ScreenCapturerSwizzle] getDisplayMedia:result: method not found");
            return;
        }
        
        _originalGetDisplayMedia = method_getImplementation(originalMethod);
        method_setImplementation(originalMethod, (IMP)swizzled_getDisplayMedia);
    });
}

// Auto-install on app launch
__attribute__((constructor))
static void AutoInstallScreenCapturerSwizzle(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), 
                  dispatch_get_main_queue(), ^{
        InstallScreenCapturerSwizzle();
    });
}

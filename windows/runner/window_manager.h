//
//  window_manager.h
//  Flutter Host - Windows
//
//  Handles window discovery and manipulation via Win32 APIs on Windows.
//  Provides method channel handler for "app.afkdev.window_manager".
//

#ifndef RUNNER_WINDOW_MANAGER_H_
#define RUNNER_WINDOW_MANAGER_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

// Registers the window manager method channel with the Flutter engine.
void RegisterWindowManagerChannel(flutter::FlutterEngine* engine);

#endif  // RUNNER_WINDOW_MANAGER_H_

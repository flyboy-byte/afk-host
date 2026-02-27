//
//  input_injection.h
//  Flutter Host - Windows
//
//  Handles input injection via SendInput API on Windows.
//  Provides method channel handler for "app.afkdev.input_injection".
//

#ifndef RUNNER_INPUT_INJECTION_H_
#define RUNNER_INPUT_INJECTION_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

// Registers the input injection method channel with the Flutter engine.
void RegisterInputInjectionChannel(flutter::FlutterEngine* engine);

#endif  // RUNNER_INPUT_INJECTION_H_

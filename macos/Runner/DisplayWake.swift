//
//  DisplayWake.swift
//  Runner
//
//  Wakes the display when a remote connection is initiated.
//  Uses IOKit power management to trigger user activity.
//

import FlutterMacOS
import IOKit.pwr_mgt

class DisplayWakePlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "app.afkdev.display_wake",
            binaryMessenger: registrar.messenger
        )
        let instance = DisplayWakePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "wakeDisplay":
            let success = wakeDisplayIfNeeded()
            result(success)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func wakeDisplayIfNeeded() -> Bool {
        var assertionID: IOPMAssertionID = 0
        let assertionResult = IOPMAssertionDeclareUserActivity(
            "Remote connection initiated" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )

        if assertionResult == kIOReturnSuccess {
            NSLog("[DisplayWake] Display wake triggered")
            return true
        } else {
            NSLog("[DisplayWake] Failed to wake display, error code: \(assertionResult)")
            return false
        }
    }
}

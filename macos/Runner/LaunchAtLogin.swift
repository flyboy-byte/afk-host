//
//  LaunchAtLogin.swift
//  Runner
//
//  Manages app launch at login using SMAppService (macOS 13+).
//  Allows users to enable/disable automatic startup on macOS login.
//

import FlutterMacOS
import ServiceManagement

class LaunchAtLoginPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "app.afkdev.launch_at_login",
            binaryMessenger: registrar.messenger
        )
        let instance = LaunchAtLoginPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isEnabled":
            result(isLaunchAtLoginEnabled())

        case "setEnabled":
            guard let args = call.arguments as? [String: Any],
                  let enabled = args["enabled"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected 'enabled' bool", details: nil))
                return
            }
            let success = setLaunchAtLogin(enabled: enabled)
            result(success)

        case "isSupported":
            if #available(macOS 13.0, *) {
                result(true)
            } else {
                result(false)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Not supported on older macOS versions
            return false
        }
    }

    private func setLaunchAtLogin(enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else {
            NSLog("[LaunchAtLogin] SMAppService requires macOS 13.0+")
            return false
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
                NSLog("[LaunchAtLogin] Registered for launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                NSLog("[LaunchAtLogin] Unregistered from launch at login")
            }
            return true
        } catch {
            NSLog("[LaunchAtLogin] Failed to set launch at login: \(error)")
            return false
        }
    }
}

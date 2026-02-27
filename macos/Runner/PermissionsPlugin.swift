//
//  PermissionsPlugin.swift
//  Runner
//
//  Handles permission checking and requesting for Screen Recording and Accessibility.
//  Registered as a method channel handler for "app.afkdev.permissions".
//

import AppKit
import ApplicationServices
import FlutterMacOS

class PermissionsPlugin: NSObject, FlutterPlugin {
    // MARK: - Plugin Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "app.afkdev.permissions",
            binaryMessenger: registrar.messenger
        )
        let instance = PermissionsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: - FlutterPlugin

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkScreenRecording":
            result(checkScreenRecordingPermission())

        case "requestScreenRecording":
            requestScreenRecordingPermission()
            result(nil)

        case "checkAccessibility":
            result(checkAccessibilityPermission())

        case "requestAccessibility":
            requestAccessibilityPermission()
            result(nil)

        case "checkAll":
            result([
                "screenRecording": checkScreenRecordingPermission(),
                "accessibility": checkAccessibilityPermission(),
            ])

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Screen Recording

    private func checkScreenRecordingPermission() -> Bool {
        // CGPreflightScreenCaptureAccess returns true if we have permission
        return CGPreflightScreenCaptureAccess()
    }

    private func requestScreenRecordingPermission() {
        // Lower any floating windows first so system dialog is visible
        lowerFloatingWindows()

        // First, attempt a screen capture to ensure the app appears in System Settings list.
        // This is required on newer macOS versions - apps only appear in the Screen Recording
        // privacy list after they actually attempt to capture the screen.
        triggerScreenCaptureAttempt()

        // CGRequestScreenCaptureAccess:
        // - Shows system prompt the FIRST time (returns false while prompting)
        // - Returns true if already granted
        // - Returns false if denied or not yet granted
        let granted = CGRequestScreenCaptureAccess()

        // Only open Settings if not granted (prompt was already shown before, or user denied)
        if !granted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Attempt a screen capture to trigger macOS to add this app to the Screen Recording list.
    private func triggerScreenCaptureAttempt() {
        // CGWindowListCreateImage will trigger the permission prompt and add the app to the list
        let _ = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    private func requestAccessibilityPermission() {
        // Lower any floating windows first
        lowerFloatingWindows()

        // Prompt for accessibility permission
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Helpers

    private func lowerFloatingWindows() {
        // Lower floating windows so system permission dialogs are visible
        for window in NSApp.windows where window.level == .floating {
            window.level = .normal
        }
    }
}

//
//  AppState.swift
//  Runner
//
//  Holds the app state displayed by the native menu bar UI.
//  Updated by Flutter services via AppHostPlugin method channel.
//

import Combine
import FlutterMacOS
import Foundation

/// Observable app state for native SwiftUI menu bar view.
/// Flutter services update this state via method channel calls.
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published Properties

    @Published var isConnectedToServer = false
    @Published var isStreaming = false
    @Published var connectedClientCount = 0
    @Published var pairedDeviceCount = 0
    @Published var pairedDeviceNames: [String] = []
    @Published var statusMessage = "Initializing..."
    @Published var errorMessage: String?

    // MARK: - Flutter Communication

    weak var flutterViewController: FlutterViewController?
    private var methodChannel: FlutterMethodChannel?

    private init() {
        refreshCliStatus()
    }

    func setupMethodChannel(with messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "app.afkdev.app_host",
            binaryMessenger: messenger
        )

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
    }

    // MARK: - Method Call Handler

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "updateState":
            handleUpdateState(call.arguments, result: result)

        case "notifyPairingComplete":
            handlePairingComplete(call.arguments, result: result)

        case "showMainWindow":
            showMainWindow()
            result(nil)

        case "hideMainWindow":
            hideMainWindow()
            result(nil)

        case "isCliInstalled":
            refreshCliStatus()
            result(isCliInstalled)

        case "installCLI":
            result(installCLI())

        case "uninstallCLI":
            result(uninstallCLI())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Window Control

    private func showMainWindow() {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow {
                window.showWindow()
            }
        }
    }

    private func hideMainWindow() {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow {
                window.orderOut(nil)
            }
        }
    }

    private func handleUpdateState(_ arguments: Any?, result: FlutterResult) {
        guard let args = arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary", details: nil))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let isConnected = args["isConnectedToServer"] as? Bool {
                self.isConnectedToServer = isConnected
            }
            if let streaming = args["isStreaming"] as? Bool {
                self.isStreaming = streaming
            }
            if let clientCount = args["connectedClientCount"] as? Int {
                self.connectedClientCount = clientCount
            }
            if let pairedCount = args["pairedDeviceCount"] as? Int {
                self.pairedDeviceCount = pairedCount
            }
            if let names = args["pairedDeviceNames"] as? [String] {
                self.pairedDeviceNames = names
            }
            if let status = args["statusMessage"] as? String {
                self.statusMessage = status
            }
            if let error = args["errorMessage"] as? String {
                self.errorMessage = error.isEmpty ? nil : error
            } else {
                self.errorMessage = nil
            }
        }

        result(nil)
    }

    private func handlePairingComplete(_ arguments: Any?, result: FlutterResult) {
        guard arguments is [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary", details: nil))
            return
        }
        result(nil)
    }

    // MARK: - CLI Installation

    /// Whether the `afk` CLI is already installed in PATH.
    @Published var isCliInstalled = false

    /// Show setup hint after a fresh CLI install.
    @Published var showCliSetupHint = false

    private let cliInstallPath = "/usr/local/bin/afk"

    /// Check if the CLI symlink exists and points to our bundled CLI.
    func refreshCliStatus() {
        let fm = FileManager.default
        isCliInstalled = fm.fileExists(atPath: cliInstallPath)
    }

    /// Path to the bundled CLI launcher inside the app bundle.
    private var bundledCliPath: String? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let path = resourcePath + "/cli/afk"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Install the `afk` CLI by symlinking /usr/local/bin/afk → bundled CLI.
    /// Returns a result dictionary with success status and error details if failed.
    func installCLI() -> [String: Any] {
        guard let source = bundledCliPath else {
            return [
                "success": false,
                "error": "CLI not found in app bundle",
                "errorType": "not_found"
            ]
        }

        let fm = FileManager.default
        let destination = cliInstallPath
        let destDir = (destination as NSString).deletingLastPathComponent
        let command = "sudo ln -sf '\(source)' '\(destination)'"

        do {
            if !fm.fileExists(atPath: destDir) {
                try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            }
            // Remove existing symlink/file first
            if fm.fileExists(atPath: destination) || (try? fm.attributesOfItem(atPath: destination)) != nil {
                try fm.removeItem(atPath: destination)
            }
            try fm.createSymbolicLink(atPath: destination, withDestinationPath: source)
            DispatchQueue.main.async { [weak self] in
                self?.isCliInstalled = true
                self?.showCliSetupHint = true
                self?.errorMessage = nil
            }
            return ["success": true]
        } catch let error as NSError {
            NSLog("[AFK] CLI install failed: \(error)")
            let isPermissionError = error.domain == NSCocoaErrorDomain &&
                (error.code == NSFileWriteNoPermissionError || error.code == NSFileNoSuchFileError)
            
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = error.localizedDescription
            }
            
            return [
                "success": false,
                "error": error.localizedDescription,
                "errorType": isPermissionError ? "permission" : "unknown",
                "command": command
            ]
        }
    }

    /// Remove the `afk` CLI symlink from /usr/local/bin.
    /// Returns a result dictionary with success status and error details if failed.
    func uninstallCLI() -> [String: Any] {
        let fm = FileManager.default
        let destination = cliInstallPath
        let command = "sudo rm '\(destination)'"

        do {
            if fm.fileExists(atPath: destination) || (try? fm.attributesOfItem(atPath: destination)) != nil {
                try fm.removeItem(atPath: destination)
            }
            DispatchQueue.main.async { [weak self] in
                self?.isCliInstalled = false
                self?.showCliSetupHint = false
                self?.errorMessage = nil
            }
            return ["success": true]
        } catch let error as NSError {
            NSLog("[AFK] CLI uninstall failed: \(error)")
            let isPermissionError = error.domain == NSCocoaErrorDomain &&
                (error.code == NSFileWriteNoPermissionError || error.code == NSFileNoSuchFileError)
            
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = error.localizedDescription
            }
            
            return [
                "success": false,
                "error": error.localizedDescription,
                "errorType": isPermissionError ? "permission" : "unknown",
                "command": command
            ]
        }
    }

    // MARK: - Actions (Native -> Flutter)

    func showPairingWindow() {
        methodChannel?.invokeMethod("showPairing", arguments: nil)
        showFlutterWindow()
    }

    func showSettingsWindow() {
        methodChannel?.invokeMethod("showSettings", arguments: nil)
        showFlutterWindow()
    }

    private func showFlutterWindow() {
        if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow {
            window.showWindow()
        } else if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func requestQuit() {
        methodChannel?.invokeMethod("quit", arguments: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}

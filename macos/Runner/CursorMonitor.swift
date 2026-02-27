//
//  CursorMonitor.swift
//  Runner
//
//  Monitors macOS system cursor changes and sends cursor image data
//  to Flutter for transmission to iOS clients via WebRTC data channel.
//  Polls NSCursor.currentSystem and detects changes via image hash comparison.
//

import AppKit
import FlutterMacOS
import Foundation

class CursorMonitor: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var pollTimer: Timer?
    private var lastCursorHash: Int?
    private var isMonitoring = false

    // Polling interval in seconds (50ms for responsive cursor updates)
    private let pollingInterval: TimeInterval = 0.05

    // MARK: - FlutterPlugin Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "app.afkdev.cursor_monitor",
            binaryMessenger: registrar.messenger
        )
        let instance = CursorMonitor()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        NSLog("[CursorMonitor] Plugin registered")
    }

    // MARK: - FlutterPlugin Method Handling

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startMonitoring":
            startMonitoring()
            result(nil)

        case "stopMonitoring":
            stopMonitoring()
            result(nil)

        case "getCurrentCursor":
            if let cursorData = getCurrentCursorData() {
                result(cursorData)
            } else {
                result(nil)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Public Methods

    func startMonitoring() {
        // Ensure we're on main thread (NSCursor must be accessed from main thread)
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startMonitoring()
            }
            return
        }

        guard !isMonitoring else {
            NSLog("[CursorMonitor] Already monitoring")
            return
        }

        NSLog("[CursorMonitor] Starting cursor monitoring at \(pollingInterval * 1000)ms interval")

        isMonitoring = true
        lastCursorHash = nil

        // Get initial cursor state
        checkCursorState()

        // Start periodic monitoring
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.checkCursorState()
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        NSLog("[CursorMonitor] Stopping cursor monitoring")

        pollTimer?.invalidate()
        pollTimer = nil
        isMonitoring = false
        lastCursorHash = nil
    }

    // MARK: - Private Methods

    private func checkCursorState() {
        guard let cursor = NSCursor.currentSystem else {
            return
        }

        let image = cursor.image
        let hotSpot = cursor.hotSpot

        // Compute hash from image data to detect changes
        guard let tiffData = image.tiffRepresentation else {
            return
        }

        let currentHash = tiffData.hashValue

        // Only send if cursor changed
        guard currentHash != lastCursorHash else {
            return
        }

        lastCursorHash = currentHash

        // Convert to PNG for efficient transmission
        guard let pngData = convertToPNG(image: image) else {
            NSLog("[CursorMonitor] Failed to convert cursor to PNG")
            return
        }

        // Build cursor data dictionary
        let cursorData: [String: Any] = [
            "imageData": pngData.base64EncodedString(),
            "hotSpotX": hotSpot.x,
            "hotSpotY": hotSpot.y,
            "width": image.size.width,
            "height": image.size.height,
            "hash": currentHash,
        ]

        // Send to Flutter via method channel
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("onCursorChanged", arguments: cursorData)
        }
    }

    private func getCurrentCursorData() -> [String: Any]? {
        guard let cursor = NSCursor.currentSystem else {
            return nil
        }

        let image = cursor.image
        let hotSpot = cursor.hotSpot

        guard let tiffData = image.tiffRepresentation else {
            return nil
        }

        guard let pngData = convertToPNG(image: image) else {
            return nil
        }

        return [
            "imageData": pngData.base64EncodedString(),
            "hotSpotX": hotSpot.x,
            "hotSpotY": hotSpot.y,
            "width": image.size.width,
            "height": image.size.height,
            "hash": tiffData.hashValue,
        ]
    }

    private func convertToPNG(image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}

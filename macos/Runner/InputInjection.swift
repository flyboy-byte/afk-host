//
//  InputInjection.swift
//  Runner
//
//  Handles input injection via CGEvent APIs on macOS.
//  Registered as a method channel handler for "app.afkdev.input_injection".
//

import AppKit
import ApplicationServices
import Cocoa
import FlutterMacOS

class InputInjection: NSObject, FlutterPlugin {
    
    // MARK: - Properties
    
    private var isMouseButtonDown = false
    private var lastMousePosition = CGPoint.zero
    
    // Track active modifiers for key combinations
    private var activeModifiers: CGEventFlags = []
    
    // MARK: - Plugin Registration
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "app.afkdev.input_injection",
            binaryMessenger: registrar.messenger
        )
        let instance = InputInjection()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    // MARK: - FlutterPlugin
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Handle methods that don't require arguments first
        switch call.method {
        case "checkAccessibility":
            let hasAccess = checkAccessibilityPermissions()
            result(hasAccess)
            return
            
        case "requestAccessibility":
            requestAccessibilityPermissions()
            result(nil)
            return

        default:
            break
        }
        
        // All other methods require dictionary arguments
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary arguments", details: nil))
            return
        }
        
        switch call.method {
        case "mouseMove":
            guard let x = args["x"] as? Double,
                  let y = args["y"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "mouseMove requires x, y", details: nil))
                return
            }
            let success = handleMouseMove(x: x, y: y)
            result(success)
            
        case "mouseDown":
            guard let x = args["x"] as? Double,
                  let y = args["y"] as? Double,
                  let button = args["button"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "mouseDown requires x, y, button", details: nil))
                return
            }
            let success = handleMouseDown(x: x, y: y, button: button)
            result(success)
            
        case "mouseUp":
            guard let x = args["x"] as? Double,
                  let y = args["y"] as? Double,
                  let button = args["button"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "mouseUp requires x, y, button", details: nil))
                return
            }
            let success = handleMouseUp(x: x, y: y, button: button)
            result(success)
            
        case "doubleClick":
            guard let x = args["x"] as? Double,
                  let y = args["y"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "doubleClick requires x, y", details: nil))
                return
            }
            let success = handleDoubleClick(x: x, y: y)
            result(success)
            
        case "scroll":
            guard let x = args["x"] as? Double,
                  let y = args["y"] as? Double,
                  let deltaX = args["deltaX"] as? Double,
                  let deltaY = args["deltaY"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "scroll requires x, y, deltaX, deltaY", details: nil))
                return
            }
            let success = handleScroll(x: x, y: y, deltaX: deltaX, deltaY: deltaY)
            result(success)
            
        case "keyDown":
            guard let keyCode = args["keyCode"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "keyDown requires keyCode", details: nil))
                return
            }
            let success = handleKeyDown(keysym: keyCode)
            result(success)
            
        case "keyUp":
            guard let keyCode = args["keyCode"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "keyUp requires keyCode", details: nil))
                return
            }
            let success = handleKeyUp(keysym: keyCode)
            result(success)
            
        case "keyPress":
            guard let keyCode = args["keyCode"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "keyPress requires keyCode", details: nil))
                return
            }
            let character = args["character"] as? String
            let success = handleKeyPress(keysym: keyCode, character: character)
            result(success)
            
        case "pasteText":
            guard let text = args["text"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "pasteText requires text", details: nil))
                return
            }
            let success = handlePasteText(text: text)
            result(success)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Accessibility Permissions
    
    private func checkAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            NSLog("[InputInjection] Accessibility permissions not granted")
        }
        return trusted
    }
    
    private func requestAccessibilityPermissions() {
        // Prompt the user to grant accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Coordinate Transformation
    
    /// Transform normalized coordinates (0-1) to screen coordinates.
    private func transformToScreenCoordinates(x: Double, y: Double) -> CGPoint? {
        guard let mainScreen = NSScreen.main else {
            NSLog("[InputInjection] No main screen available")
            return nil
        }
        
        let screenFrame = mainScreen.frame
        
        // x and y are normalized (0-1), convert to screen pixels
        let screenX = x * screenFrame.width
        // Note: macOS screen coordinates have origin at bottom-left, but CGEvent uses top-left
        // For screen capture, the video coordinates are typically top-left origin
        let screenY = y * screenFrame.height
        
        // Validate coordinates are within reasonable bounds
        guard screenX >= 0, screenX <= screenFrame.width,
              screenY >= 0, screenY <= screenFrame.height else {
            NSLog("[InputInjection] Coordinates out of bounds: (\(screenX), \(screenY))")
            return nil
        }
        
        return CGPoint(x: screenX, y: screenY)
    }
    
    // MARK: - Mouse Event Handling
    
    private func handleMouseMove(x: Double, y: Double) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        guard let screenPoint = transformToScreenCoordinates(x: x, y: y) else {
            return false
        }
        
        let eventType: CGEventType = isMouseButtonDown ? .leftMouseDragged : .mouseMoved
        let mouseEvent = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: screenPoint, mouseButton: .left)
        mouseEvent?.post(tap: .cgSessionEventTap)
        
        lastMousePosition = screenPoint
        return true
    }
    
    private func handleMouseDown(x: Double, y: Double, button: Int) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        guard let screenPoint = transformToScreenCoordinates(x: x, y: y) else {
            return false
        }
        
        // Move cursor to position first
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: screenPoint, mouseButton: .left)
        moveEvent?.post(tap: .cgSessionEventTap)
        
        // Send mouse down event
        let eventType: CGEventType = button == 1 ? .rightMouseDown : .leftMouseDown
        let mouseButton: CGMouseButton = button == 1 ? .right : .left
        let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: screenPoint, mouseButton: mouseButton)
        mouseDownEvent?.post(tap: .cgSessionEventTap)
        
        if button == 0 {
            isMouseButtonDown = true
        }
        lastMousePosition = screenPoint
        return true
    }
    
    private func handleMouseUp(x: Double, y: Double, button: Int) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        guard let screenPoint = transformToScreenCoordinates(x: x, y: y) else {
            return false
        }
        
        // Send mouse up event
        let eventType: CGEventType = button == 1 ? .rightMouseUp : .leftMouseUp
        let mouseButton: CGMouseButton = button == 1 ? .right : .left
        let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: screenPoint, mouseButton: mouseButton)
        mouseUpEvent?.post(tap: .cgSessionEventTap)
        
        if button == 0 {
            isMouseButtonDown = false
        }
        lastMousePosition = screenPoint
        return true
    }
    
    private func handleDoubleClick(x: Double, y: Double) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        guard let screenPoint = transformToScreenCoordinates(x: x, y: y) else {
            return false
        }
        
        // Move cursor to position first
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: screenPoint, mouseButton: .left)
        moveEvent?.post(tap: .cgSessionEventTap)
        
        // First click with count=1
        let firstDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: screenPoint, mouseButton: .left)
        firstDown?.setIntegerValueField(.mouseEventClickState, value: 1)
        firstDown?.post(tap: .cgSessionEventTap)
        
        let firstUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: screenPoint, mouseButton: .left)
        firstUp?.setIntegerValueField(.mouseEventClickState, value: 1)
        firstUp?.post(tap: .cgSessionEventTap)
        
        // Very short delay between clicks
        usleep(50000) // 50ms - within macOS double-click threshold
        
        // Second click with count=2 (this makes it a double-click)
        let secondDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: screenPoint, mouseButton: .left)
        secondDown?.setIntegerValueField(.mouseEventClickState, value: 2)
        secondDown?.post(tap: .cgSessionEventTap)
        
        let secondUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: screenPoint, mouseButton: .left)
        secondUp?.setIntegerValueField(.mouseEventClickState, value: 2)
        secondUp?.post(tap: .cgSessionEventTap)
        
        lastMousePosition = screenPoint
        return true
    }
    
    private func handleScroll(x: Double, y: Double, deltaX: Double, deltaY: Double) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        guard let screenPoint = transformToScreenCoordinates(x: x, y: y) else {
            return false
        }
        
        // Create scroll event
        let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(deltaY), wheel2: Int32(deltaX), wheel3: 0)
        scrollEvent?.location = screenPoint
        scrollEvent?.post(tap: .cgSessionEventTap)
        
        return true
    }
    
    // MARK: - Key Event Handling
    
    /// Map X11 keysym codes to macOS virtual key codes (CGKeyCode).
    /// Standard protocol used by VNC, RDP, and other remote desktop systems.
    private func mapX11KeysymToMacKeyCode(_ keysym: Int) -> CGKeyCode? {
        // Modifiers (X11 keysym → macOS CGKeyCode)
        if keysym == 0xFFE1 { return 0x38 } // Shift_L → Shift
        if keysym == 0xFFE3 { return 0x3B } // Control_L → Control
        if keysym == 0xFFE9 { return 0x3A } // Alt_L → Option
        if keysym == 0xFFEB { return 0x37 } // Super_L (Command) → Command
        
        // Navigation and special keys
        if keysym == 0xFF09 { return 0x30 } // Tab → Tab
        if keysym == 0xFF0D { return 0x24 } // Return → Return
        if keysym == 0xFF1B { return 0x35 } // Escape → Escape
        if keysym == 0x0020 { return 0x31 } // Space → Space
        if keysym == 0xFF08 { return 0x33 } // BackSpace → Delete
        
        // Arrow keys
        if keysym == 0xFF51 { return 0x7B } // Left → Left
        if keysym == 0xFF52 { return 0x7E } // Up → Up
        if keysym == 0xFF53 { return 0x7C } // Right → Right
        if keysym == 0xFF54 { return 0x7D } // Down → Down
        
        // Numbers 0-9 (ASCII range)
        if keysym == 48 { return 0x1D } // 0
        if keysym == 49 { return 0x12 } // 1
        if keysym == 50 { return 0x13 } // 2
        if keysym == 51 { return 0x14 } // 3
        if keysym == 52 { return 0x15 } // 4
        if keysym == 53 { return 0x17 } // 5
        if keysym == 54 { return 0x16 } // 6
        if keysym == 55 { return 0x1A } // 7
        if keysym == 56 { return 0x1C } // 8
        if keysym == 57 { return 0x19 } // 9
        
        // Letters a-z (ASCII lowercase; macOS uses ANSI virtual key codes)
        if keysym == 97 { return 0x00 } // a
        if keysym == 98 { return 0x0B } // b
        if keysym == 99 { return 0x08 } // c
        if keysym == 100 { return 0x02 } // d
        if keysym == 101 { return 0x0E } // e
        if keysym == 102 { return 0x03 } // f
        if keysym == 103 { return 0x05 } // g
        if keysym == 104 { return 0x04 } // h
        if keysym == 105 { return 0x22 } // i
        if keysym == 106 { return 0x26 } // j
        if keysym == 107 { return 0x28 } // k
        if keysym == 108 { return 0x25 } // l
        if keysym == 109 { return 0x2E } // m
        if keysym == 110 { return 0x2D } // n
        if keysym == 111 { return 0x1F } // o
        if keysym == 112 { return 0x23 } // p
        if keysym == 113 { return 0x0C } // q
        if keysym == 114 { return 0x0F } // r
        if keysym == 115 { return 0x01 } // s
        if keysym == 116 { return 0x11 } // t
        if keysym == 117 { return 0x20 } // u
        if keysym == 118 { return 0x09 } // v
        if keysym == 119 { return 0x0D } // w
        if keysym == 120 { return 0x07 } // x
        if keysym == 121 { return 0x10 } // y
        if keysym == 122 { return 0x06 } // z
        
        // Common punctuation (US keyboard layout)
        if keysym == 46 { return 0x2F } // . (period)
        if keysym == 47 { return 0x2C } // / (slash)
        if keysym == 44 { return 0x2B } // , (comma)
        if keysym == 59 { return 0x29 } // ; (semicolon)
        if keysym == 39 { return 0x27 } // ' (apostrophe/single quote)
        if keysym == 45 { return 0x1B } // - (minus/hyphen)
        if keysym == 61 { return 0x18 } // = (equals)
        if keysym == 91 { return 0x21 } // [ (left bracket)
        if keysym == 93 { return 0x1E } // ] (right bracket)
        if keysym == 92 { return 0x2A } // \ (backslash)
        if keysym == 96 { return 0x32 } // ` (grave/backtick)
        
        // Shifted symbols - map to base key (shift modifier handled separately)
        if keysym == 33 { return 0x12 } // ! → 1 key
        if keysym == 64 { return 0x13 } // @ → 2 key
        if keysym == 35 { return 0x14 } // # → 3 key
        if keysym == 36 { return 0x15 } // $ → 4 key
        if keysym == 37 { return 0x17 } // % → 5 key
        if keysym == 94 { return 0x16 } // ^ → 6 key
        if keysym == 38 { return 0x1A } // & → 7 key
        if keysym == 42 { return 0x1C } // * → 8 key
        if keysym == 40 { return 0x19 } // ( → 9 key
        if keysym == 41 { return 0x1D } // ) → 0 key
        if keysym == 95 { return 0x1B } // _ → minus key (shifted)
        if keysym == 43 { return 0x18 } // + → equals key (shifted)
        if keysym == 123 { return 0x21 } // { → left bracket (shifted)
        if keysym == 125 { return 0x1E } // } → right bracket (shifted)
        if keysym == 124 { return 0x2A } // | → backslash (shifted)
        if keysym == 58 { return 0x29 } // : → semicolon (shifted)
        if keysym == 34 { return 0x27 } // " → apostrophe (shifted)
        if keysym == 60 { return 0x2B } // < → comma (shifted)
        if keysym == 62 { return 0x2F } // > → period (shifted)
        if keysym == 63 { return 0x2C } // ? → slash (shifted)
        if keysym == 126 { return 0x32 } // ~ → grave (shifted)
        
        // Unsupported keysym
        return nil
    }
    
    private func handleKeyDown(keysym: Int) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        guard let cgKeyCode = mapX11KeysymToMacKeyCode(keysym) else {
            NSLog("[InputInjection] Unsupported X11 keysym: 0x\(String(keysym, radix: 16))")
            return false
        }
        
        // Update modifier state FIRST before creating the event
        updateModifierState(keyCode: cgKeyCode, isDown: true)
        
        let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: cgKeyCode, keyDown: true)
        // For modifier keys themselves, don't set flags (they ARE the modifier)
        // For non-modifier keys, apply the current active modifiers
        if !isModifierKey(cgKeyCode) {
            keyDownEvent?.flags = activeModifiers
        }
        keyDownEvent?.post(tap: .cgSessionEventTap)
        
        return true
    }
    
    private func handleKeyUp(keysym: Int) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        guard let cgKeyCode = mapX11KeysymToMacKeyCode(keysym) else {
            NSLog("[InputInjection] Unsupported X11 keysym: 0x\(String(keysym, radix: 16))")
            return false
        }
        
        let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: cgKeyCode, keyDown: false)
        // For modifier keys themselves, don't set flags (they ARE the modifier)
        // For non-modifier keys, apply the current active modifiers
        if !isModifierKey(cgKeyCode) {
            keyUpEvent?.flags = activeModifiers
        }
        keyUpEvent?.post(tap: .cgSessionEventTap)
        
        // Update modifier state AFTER posting the event for UP
        updateModifierState(keyCode: cgKeyCode, isDown: false)
        
        return true
    }
    
    private func handleKeyPress(keysym: Int, character: String?) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        guard let cgKeyCode = mapX11KeysymToMacKeyCode(keysym) else {
            NSLog("[InputInjection] Unsupported X11 keysym: 0x\(String(keysym, radix: 16))")
            return false
        }
        
        // Use HID system state for better event source (industry best practice)
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Create key down event with active modifiers applied
        guard let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: cgKeyCode, keyDown: true) else {
            return false
        }
        
        // Set modifier flags (physical state)
        var modifiers = activeModifiers
        
        // macOS automatically sets kCGEventFlagMaskSecondaryFn for arrow keys,
        // function keys, and other navigation keys when pressed on physical keyboards.
        let isArrowKey = (cgKeyCode == 0x7B || cgKeyCode == 0x7C || cgKeyCode == 0x7D || cgKeyCode == 0x7E)
        let isFunctionKey = (cgKeyCode >= 0x7A && cgKeyCode <= 0x69) // F1-F12 range (approximation)
        
        if isArrowKey || isFunctionKey {
            modifiers.insert(CGEventFlags(rawValue: 0x0080_0000)) // kCGEventFlagMaskSecondaryFn
        }
        
        keyDownEvent.flags = modifiers
        
        // Set Unicode character override (logical state)
        if let character = character, !character.isEmpty {
            var unicodeChars = Array(character.utf16)
            keyDownEvent.keyboardSetUnicodeString(
                stringLength: unicodeChars.count,
                unicodeString: &unicodeChars
            )
        }
        
        // Use cgSessionEventTap for system-level shortcuts like Mission Control space switching
        keyDownEvent.post(tap: .cgSessionEventTap)
        
        // Small delay between down and up
        usleep(10000) // 0.01 seconds
        
        // Create key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: cgKeyCode, keyDown: false) else {
            return false
        }
        
        // Use the same modifiers as key down
        keyUpEvent.flags = modifiers
        
        // Set Unicode on key up as well for consistency
        if let character = character, !character.isEmpty {
            var unicodeChars = Array(character.utf16)
            keyUpEvent.keyboardSetUnicodeString(
                stringLength: unicodeChars.count,
                unicodeString: &unicodeChars
            )
        }
        
        keyUpEvent.post(tap: .cgSessionEventTap)
        
        return true
    }
    
    // Helper to check if a key code is a modifier key
    private func isModifierKey(_ keyCode: CGKeyCode) -> Bool {
        switch keyCode {
        case 0x37, 0x38, 0x3A, 0x3B: // Command, Shift, Option, Control
            return true
        default:
            return false
        }
    }
    
    // Update active modifier flags based on key down/up events
    private func updateModifierState(keyCode: CGKeyCode, isDown: Bool) {
        let modifierFlag: CGEventFlags? = {
            switch keyCode {
            case 0x37: // Command
                return .maskCommand
            case 0x38: // Shift
                return .maskShift
            case 0x3A: // Option
                return .maskAlternate
            case 0x3B: // Control
                return .maskControl
            default:
                return nil
            }
        }()
        
        if let flag = modifierFlag {
            if isDown {
                activeModifiers.insert(flag)
            } else {
                activeModifiers.remove(flag)
            }
        }
    }
    
    // MARK: - Text Paste
    
    private func handlePasteText(text: String) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        // Copy text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            NSLog("[InputInjection] Failed to copy text to clipboard")
            return false
        }
        
        // Simulate Cmd+V by posting V key events with Command flag set directly
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        
        vKeyDown?.flags = .maskCommand
        vKeyUp?.flags = .maskCommand
        
        vKeyDown?.post(tap: .cghidEventTap)
        vKeyUp?.post(tap: .cghidEventTap)
        
        return true
    }
}

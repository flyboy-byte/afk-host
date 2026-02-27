//
//  MainFlutterWindow.swift
//  Runner
//
//  Main Flutter window that hosts the FlutterViewController.
//  Sets up the menu bar UI and manages window visibility.
//  In menu bar mode, this window is hidden by default and shown on demand.
//

import Cocoa
import FlutterMacOS
import SwiftUI

class MainFlutterWindow: NSWindow {
    
    // Menu bar components (static so they persist)
    private static var statusItem: NSStatusItem?
    private static var popover: NSPopover?
    private static var eventMonitor: Any?
    
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = frame
        contentViewController = flutterViewController
        setFrame(windowFrame, display: false)

        RegisterGeneratedPlugins(registry: flutterViewController)

        // Register custom plugins
        InputInjection.register(with: flutterViewController.registrar(forPlugin: "InputInjection"))
        WindowManager.register(with: flutterViewController.registrar(forPlugin: "WindowManager"))
        CursorMonitor.register(with: flutterViewController.registrar(forPlugin: "CursorMonitor"))
        DisplayWakePlugin.register(with: flutterViewController.registrar(forPlugin: "DisplayWakePlugin"))
        LaunchAtLoginPlugin.register(with: flutterViewController.registrar(forPlugin: "LaunchAtLoginPlugin"))
        PermissionsPlugin.register(with: flutterViewController.registrar(forPlugin: "PermissionsPlugin"))
        
        // Set up AppState method channel for native <-> Flutter communication
        AppState.shared.setupMethodChannel(with: flutterViewController.engine.binaryMessenger)
        AppState.shared.flutterViewController = flutterViewController

        // Configure window as a fixed-size panel with seamless title bar
        self.title = "AFK Host"
        self.styleMask = [.titled, .closable, .fullSizeContentView]
        self.isReleasedWhenClosed = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .visible
        self.backgroundColor = NSColor(red: 0x1E/255, green: 0x1E/255, blue: 0x1E/255, alpha: 1.0)
        self.isMovableByWindowBackground = true
        
        // Fixed size - sidebar layout
        let fixedSize = NSSize(width: 560, height: 400)
        self.setContentSize(fixedSize)
        self.minSize = fixedSize
        self.maxSize = fixedSize
        
        // Set up the menu bar
        setupMenuBar()

        super.awakeFromNib()
        
        // Window starts hidden (set in XIB), center it for when shown
        self.center()
        
        // Brief show/hide to properly initialize Flutter engine lifecycle
        DispatchQueue.main.async {
            self.orderFront(nil)
            self.orderOut(nil)
        }
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        MainFlutterWindow.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = MainFlutterWindow.statusItem?.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            } else if let image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "AFK Host") {
                button.image = image
            } else {
                button.title = "AFK"
            }
            button.target = self
            button.action = #selector(togglePopover)
        }

        MainFlutterWindow.popover = NSPopover()
        MainFlutterWindow.popover?.contentSize = NSSize(width: 260, height: 220)
        MainFlutterWindow.popover?.behavior = .transient
        MainFlutterWindow.popover?.animates = true
        MainFlutterWindow.popover?.contentViewController = NSHostingController(rootView: MenuBarView())
    }

    @objc private func togglePopover() {
        if let popover = MainFlutterWindow.popover {
            if popover.isShown {
                closePopover()
            } else {
                showPopover()
            }
        }
    }

    private func showPopover() {
        if let button = MainFlutterWindow.statusItem?.button {
            MainFlutterWindow.popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            MainFlutterWindow.eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        MainFlutterWindow.popover?.performClose(nil)

        if let monitor = MainFlutterWindow.eventMonitor {
            NSEvent.removeMonitor(monitor)
            MainFlutterWindow.eventMonitor = nil
        }
    }

    override func close() {
        orderOut(nil)
    }
    
    func showWindow() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

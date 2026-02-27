//
//  AppDelegate.swift
//  Runner
//
//  App delegate for Flutter Host menu bar app.
//  Menu bar setup is handled in MainFlutterWindow.
//

import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    override func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // Don't quit when window closes - we're a menu bar app
        false
    }

    override func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }
}

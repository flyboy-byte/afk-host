//
//  MenuBarView.swift
//  Runner
//
//  Native SwiftUI view for the menu bar popover.
//  Shows connection status and provides quick access to pairing and settings.
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with status indicator
            headerSection

            Divider()

            // Status section
            statusSection

            Divider()

            // Actions section
            actionsSection
        }
        .padding(12)
        .frame(width: 260)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "rectangle.inset.filled")
                .foregroundColor(.accentColor)

            #if DEBUG
                Text("AFK Host (Debug)")
                    .font(.headline)
                    .fontWeight(.medium)
            #else
                Text("AFK Host")
                    .font(.headline)
                    .fontWeight(.medium)
            #endif

            Spacer()

            // Connection indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }

    private var statusColor: Color {
        appState.isStreaming ? .green : .gray
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.isStreaming {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Streaming")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "circle.dotted")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Waiting for connection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 2) {
            // Pair New Device button
            Button(action: { appState.showPairingWindow() }) {
                HStack {
                    Image(systemName: "link")
                    Text("Pair New Device...")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)

            // Show paired devices count
            if appState.pairedDeviceCount > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(appState.pairedDeviceCount) device\(appState.pairedDeviceCount == 1 ? "" : "s") paired")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }

            // CLI status / link to settings
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(appState.isCliInstalled ? .green : .secondary)
                    .font(.caption)
                Text(appState.isCliInstalled ? "CLI installed" : "CLI not installed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            // Settings button
            Button(action: { appState.showSettingsWindow() }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)

            Divider()

            // Quit button
            Button(action: { appState.requestQuit() }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }
}

#if DEBUG
    struct MenuBarView_Previews: PreviewProvider {
        static var previews: some View {
            MenuBarView()
        }
    }
#endif

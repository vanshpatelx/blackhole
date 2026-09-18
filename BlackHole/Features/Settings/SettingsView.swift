import AppKit
import ServiceManagement
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(CalendarService.self) private var calendar
    @Environment(\.modelContext) private var context
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var exportMessage: String?
    @AppStorage(FloatingButtonController.enabledKey) private var floatingButton = true

    var body: some View {
        HStack(spacing: 8) {
            Card(tint: Palette.tasks) {
                VStack(alignment: .leading, spacing: 10) {
                    CardHeader(icon: "gearshape", title: "General")
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(Palette.ink)
                        .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                    Toggle("Floating button", isOn: $floatingButton)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(Palette.ink)
                    SettingRow(title: "Open workspace", value: "Hover the notch, ⌥N, or the floating button")
                    SettingRow(title: "Note → task", value: "⌘↩ on a line")
                    Spacer()
                }
                .font(.system(size: 12))
            }

            Card(tint: Palette.events) {
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(icon: "calendar", title: "Calendars") {
                        if calendar.status == .connected {
                            EllipsisMenu {
                                Button("Add Google or Outlook Account…") { calendar.openInternetAccounts() }
                                Button("Refresh") { calendar.reloadSourcesAndRefresh() }
                                Button("Calendar Privacy Settings…") { openCalendarPrivacy() }
                            }
                        }
                    }
                    switch calendar.status {
                    case .notDetermined:
                        Text("Optional. Shows today's events from Apple Calendar, including any Google, Outlook or iCloud accounts on this Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Connect Calendar") { calendar.connect() }.buttonStyle(PillButtonStyle())
                        Spacer()
                    case .denied:
                        Text("Access is off. Turn it on in System Settings to see events.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Privacy Settings…") { openCalendarPrivacy() }.buttonStyle(PillButtonStyle())
                        Spacer()
                    case .connected:
                        CalendarPicker()
                    }
                }
            }

            Card(tint: Palette.notepad) {
                VStack(alignment: .leading, spacing: 9) {
                    CardHeader(icon: "sparkles", title: "AI Assistants")
                    MCPSettings()
                    Spacer(minLength: 0)
                }
            }

            Card(tint: Palette.timer) {
                VStack(alignment: .leading, spacing: 10) {
                    CardHeader(icon: "info.circle", title: "About")
                    HStack(spacing: 8) {
                        AppMark(size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Black Hole").font(.system(size: 12, weight: .semibold))
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.inkSecondary)
                            Link("getblackhole.app", destination: URL(string: "https://getblackhole.app")!)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your data stays on this Mac")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.inkSecondary)
                        Button(exportMessage ?? "Export backup…", action: exportBackup)
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Button("Quit Black Hole") { NSApp.terminate(nil) }.buttonStyle(PillButtonStyle())
                }
            }
            .frame(width: 150)
        }
    }

    private func openCalendarPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func exportBackup() {
        guard let data = try? DataExporter.makeBackup(context: context) else {
            exportMessage = "Export failed"
            return
        }
        AppServices.shared.notch.collapse()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Black Hole Backup \(DayKey.today).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                exportMessage = "Saved"
            } catch {
                exportMessage = "Couldn't save"
            }
        }
    }
}

private struct SettingRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.medium)
            Text(value).foregroundStyle(Palette.inkSecondary)
        }
        .font(.system(size: 11.5))
    }
}

/// Every calendar on this Mac, grouped by account, with a switch to show or hide each one.
private struct CalendarPicker: View {
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(calendar.accounts) { account in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(account.title.uppercased())
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.3)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                        ForEach(account.calendars) { cal in
                            Button {
                                calendar.setVisible(!cal.isVisible, calendarID: cal.id)
                            } label: {
                                HStack(spacing: 7) {
                                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                        .fill(cal.isVisible ? cal.color : .clear)
                                        .overlay(RoundedRectangle(cornerRadius: 3.5, style: .continuous).strokeBorder(cal.color, lineWidth: 1.5))
                                        .overlay {
                                            if cal.isVisible {
                                                Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                                            }
                                        }
                                        .frame(width: 13, height: 13)
                                    Text(cal.title)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(cal.isVisible ? Palette.ink : Palette.inkSecondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button { calendar.openInternetAccounts() } label: {
                    Label("Add Google or Outlook account", systemImage: "plus.circle")
                        .labelStyle(CompactLabelStyle())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Compact MCP controls: the server switch, then one row each for web apps and the user's own network.
/// Kept tight so the whole card fits inside the notch panel.
private struct MCPSettings: View {
    @Environment(MCPServer.self) private var mcp
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SettingsToggleRow(title: "MCP server", help: "Let Claude, Cursor and other AI apps plan your day",
                              isOn: Binding(get: { mcp.config.enabled }, set: { mcp.setEnabled($0) }))

            if mcp.config.enabled {
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 5.5, height: 5.5)
                    Text(statusText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    PlainMenu {
                        ForEach(MCPServer.Client.allCases) { client in
                            Button(client.rawValue) { copy(mcp.snippet(for: client), label: client.rawValue) }
                        }
                        Divider()
                        Button("Reset Access Token") { mcp.regenerateToken() }
                    } label: {
                        Label(copied ?? "Copy setup", systemImage: copied == nil ? "doc.on.doc" : "checkmark")
                            .labelStyle(CompactLabelStyle())
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Capsule().fill(Palette.ink))
                    }
                }

                Rectangle().fill(Palette.inkTertiary.opacity(0.45)).frame(height: 0.5)

                SettingsToggleRow(title: "Web apps", help: "Public URL for claude.ai and ChatGPT connectors",
                                  isOn: Binding(get: { mcp.tunnel.state != .off }, set: { mcp.setRemoteAccess($0) }),
                                  trailing: { remoteTrailing })
                if mcp.tunnel.state != .off { remoteDetail }

                if Tailscale.isAvailable {
                    SettingsToggleRow(title: "My devices", help: "Direct access from your own machines over Tailscale, nothing public",
                                      isOn: Binding(get: { mcp.isTailnetEnabled }, set: { mcp.setTailnetAccess($0) }),
                                      trailing: { tailnetTrailing })
                }
            }
        }
    }

    @ViewBuilder
    private var remoteTrailing: some View {
        if case .running = mcp.tunnel.state, let url = mcp.connectorURL {
            CopyLinkButton(copied: copied == "url") { copy(url.absoluteString, label: "url") }
        }
    }

    @ViewBuilder
    private var tailnetTrailing: some View {
        if let url = mcp.tailnetURL {
            CopyLinkButton(copied: copied == "tailnet") { copy(url.absoluteString, label: "tailnet") }
        }
    }

    @ViewBuilder
    private var remoteDetail: some View {
        switch mcp.tunnel.state {
        case .starting:
            detailText("Opening tunnel…", color: Palette.inkSecondary)
        case .notInstalled:
            Button { copy("brew install cloudflared", label: "brew") } label: {
                detailText(copied == "brew" ? "Copied · run it, then try again" : "Needs Tailscale or cloudflared · copy install", color: Palette.ink)
            }
            .buttonStyle(.plain)
        case .failed(let reason):
            detailText(reason, color: Color(hex: 0xC92A2A))
        case .running, .off:
            PlainMenu {
                ForEach(MCPTunnel.Provider.allCases) { provider in
                    Button(provider.title) { mcp.setRemoteProvider(provider) }
                }
            } label: {
                detailText(MCPTunnel.provider == .tailscale ? "Permanent URL · Tailscale" : "Temporary URL · Cloudflare",
                           color: Palette.inkSecondary)
            }
        }
    }

    private func detailText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 1)
    }

    private var statusText: String {
        switch mcp.state {
        case .running(let port): "On · port \(port)"
        case .failed(let reason): reason
        case .off: "Starting…"
        }
    }

    private var statusColor: Color {
        switch mcp.state {
        case .running: Color(hex: 0x2F9E44)
        case .failed: Color(hex: 0xC92A2A)
        case .off: Palette.inkTertiary
        }
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { copied = label }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { if copied == label { copied = nil } } }
    }
}

/// One line: title, optional trailing control, switch.
private struct SettingsToggleRow<Trailing: View>: View {
    let title: String
    let help: String
    @Binding var isOn: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 2)
            trailing
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Palette.ink)
        }
        .frame(height: 20)
        .help(help)
    }
}

extension SettingsToggleRow where Trailing == EmptyView {
    init(title: String, help: String, isOn: Binding<Bool>) {
        self.init(title: title, help: help, isOn: isOn) { EmptyView() }
    }
}

private struct CopyLinkButton: View {
    let copied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: copied ? "checkmark" : "link")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 18)
                .background(Capsule().fill(Palette.ink))
        }
        .buttonStyle(.plain)
        .help("Copy URL")
    }
}

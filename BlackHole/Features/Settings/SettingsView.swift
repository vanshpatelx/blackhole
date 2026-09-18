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

/// Turns the local MCP server on and off and hands out client configs.
private struct MCPSettings: View {
    @Environment(MCPServer.self) private var mcp
    @State private var copied: MCPServer.Client?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: Binding(get: { mcp.config.enabled }, set: { mcp.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("MCP server").font(.system(size: 12, weight: .medium))
                    Text("Let Claude, Cursor and other AI apps plan your day")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Palette.ink)

            if mcp.config.enabled {
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(Palette.inkSecondary)

                PlainMenu {
                    ForEach(MCPServer.Client.allCases) { client in
                        Button(client.rawValue) { copy(client) }
                    }
                    Divider()
                    Button("Reset Access Token") { mcp.regenerateToken() }
                } label: {
                    Label(copied.map { "Copied for \($0.rawValue)" } ?? "Copy setup for…", systemImage: copied == nil ? "doc.on.doc" : "checkmark")
                        .labelStyle(CompactLabelStyle())
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Palette.ink))
                }

                RemoteAccessRow()
                TailnetAccessRow()
            }
        }
    }

    private var statusText: String {
        switch mcp.state {
        case .running(let port): "Running on 127.0.0.1:\(port)"
        case .failed(let reason): "Couldn't start: \(reason)"
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

    private func copy(_ client: MCPServer.Client) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mcp.snippet(for: client), forType: .string)
        withAnimation { copied = client }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = nil } }
    }
}

/// Public tunnel for cloud AI apps (claude.ai, ChatGPT) that can't reach 127.0.0.1.
private struct RemoteAccessRow: View {
    @Environment(MCPServer.self) private var mcp
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Palette.inkTertiary.opacity(0.5)).frame(height: 0.5)
            Toggle(isOn: Binding(get: { mcp.tunnel.state != .off }, set: { mcp.setRemoteAccess($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Remote access").font(.system(size: 12, weight: .medium))
                    Text("For claude.ai, ChatGPT and other web apps")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Palette.ink)

            if mcp.tunnel.state != .off {
                PlainMenu {
                    ForEach(MCPTunnel.Provider.allCases) { provider in
                        Button(provider.title) { mcp.setRemoteProvider(provider) }
                    }
                } label: {
                    Label(MCPTunnel.provider == .tailscale ? "Tailscale (permanent)" : "Cloudflare (temporary)", systemImage: "arrow.triangle.swap")
                        .labelStyle(CompactLabelStyle())
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            switch mcp.tunnel.state {
            case .off:
                EmptyView()
            case .notInstalled:
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install cloudflared", forType: .string)
                    copied = true
                } label: {
                    Text(copied ? "Copied: run it in Terminal, then toggle again" : "Needs cloudflared · Copy install command")
                        .font(.system(size: 10.5, weight: .semibold))
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            case .starting:
                Label("Opening tunnel…", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(CompactLabelStyle())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
            case .failed(let reason):
                Text(reason)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0xC92A2A))
                    .lineLimit(2)
            case .running:
                Button {
                    guard let url = mcp.connectorURL else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
                } label: {
                    Label(copied ? "Copied connector URL" : "Copy connector URL", systemImage: copied ? "checkmark" : "link")
                        .labelStyle(CompactLabelStyle())
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Palette.ink))
                }
                .buttonStyle(.plain)
                .help("Paste into claude.ai → Settings → Connectors, or ChatGPT connectors. Anyone with this URL can use your planner.")
            }
        }
    }
}

/// Direct access from the user's other machines over Tailscale: private and permanent.
private struct TailnetAccessRow: View {
    @Environment(MCPServer.self) private var mcp
    @State private var copied = false

    var body: some View {
        if Tailscale.isAvailable {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(get: { mcp.isTailnetEnabled }, set: { mcp.setTailnetAccess($0) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tailscale network").font(.system(size: 12, weight: .medium))
                        Text("Your own machines and agents, no public URL")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Palette.ink)

                if mcp.isTailnetEnabled, let url = mcp.tailnetURL {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
                    } label: {
                        Label(copied ? "Copied tailnet URL" : "Copy tailnet URL", systemImage: copied ? "checkmark" : "network")
                            .labelStyle(CompactLabelStyle())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

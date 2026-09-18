import AppKit
import SwiftUI

/// Regular window with the same workspace at a comfortable size, for longer planning sessions.
@MainActor
final class DashboardWindowController {
    private var window: NSWindow?

    func show(tab: NotchViewModel.Tab? = nil) {
        if let tab {
            AppServices.shared.notch.dashboardTab = tab
        }
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Black Hole"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            w.minSize = NSSize(width: 820, height: 420)
            let hosting = NSHostingView(rootView: DashboardView().blackHoleEnvironment())
            // Don't let SwiftUI's ideal size resize the window; cards fill whatever size the user picks.
            hosting.sizingOptions = []
            w.contentView = hosting
            w.setContentSize(NSSize(width: 980, height: 560))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct DashboardView: View {
    @Environment(NotchViewModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                AppMark(size: 22)
                Text("Black Hole").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                ChromeTabs(
                    tabs: NotchViewModel.Tab.allCases,
                    selection: Binding(get: { model.dashboardTab }, set: { model.dashboardTab = $0 })
                )
            }
            .padding(.leading, 70)

            Group {
                switch model.dashboardTab {
                case .workspace: WorkspaceView()
                case .insights: InsightsView()
                case .settings: SettingsView()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

import SwiftUI

@main
struct BlackHoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(FloatingButtonController.enabledKey) private var floatingButton = true

    var body: some Scene {
        MenuBarExtra("Black Hole", systemImage: "circle.circle.fill") {
            Button("Open Workspace  ⌥N") { AppServices.shared.notch.expand(pinned: true) }
            Button("Open Dashboard") { appDelegate.dashboard.show() }
            Toggle("Show Floating Button", isOn: $floatingButton)
            Divider()
            Button("Quit Black Hole") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dashboard = DashboardWindowController()
    private var notchController: NotchWindowController?
    private var floatingButtonController: FloatingButtonController?
    private var floatingWorkspaceController: FloatingWorkspaceController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests host inside the app; don't put a panel over the test runner's screen.
        guard NSClassFromString("XCTestCase") == nil else { return }
        let services = AppServices.shared
        services.notch.onOpenDashboard = { [weak self] in self?.dashboard.show() }
        notchController = NotchWindowController(services: services)
        floatingWorkspaceController = FloatingWorkspaceController(services: services)
        floatingButtonController = FloatingButtonController(services: services)

        // `-openWorkspace YES` (or `insights` / `settings` via `-openTab`) opens the panel on launch; handy for UI work.
        let args = UserDefaults.standard
        if args.bool(forKey: "openWorkspace") {
            if let tab = args.string(forKey: "openTab").flatMap({ NotchViewModel.Tab(rawValue: $0.capitalized) }) {
                services.notch.tab = tab
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if args.bool(forKey: "openFloating"), let screen = NSScreen.screens.first {
                    let v = screen.visibleFrame
                    services.notch.openFloating(anchor: NSRect(x: v.maxX - 60, y: v.midY - 26, width: 52, height: 52))
                } else {
                    services.notch.expand(pinned: true)
                }
            }
        }
    }
}

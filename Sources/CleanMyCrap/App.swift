import SwiftUI
import CrapCore

@main
struct CleanMyCrapApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Clean My Crap") {
            RootView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 640)
                .tint(Brand.accent)
        }
        .defaultSize(width: 1160, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Install Command Line Tool…") { Task { await CommandLineTool.install() } }
            }
            CommandGroup(after: .sidebar) {
                Button("Crap") { model.section = .crap }.keyboardShortcut("1")
                Button("Apps") { model.section = .apps }.keyboardShortcut("2")
                Divider()
            }
            CommandMenu("Crap") {
                Button("Sniff Again") { Task { await model.scan() } }
                    .keyboardShortcut("r")
                    .disabled(model.phase == .scanning || model.phase == .cleaning)
                Divider()
                Button("Select Only the Safe Stuff") { model.selectOnlySafe() }
                    .disabled(model.phase != .results)
                Button("Select Nothing") { model.selectAll(false) }
                    .disabled(model.phase != .results)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Apps dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { _ = AppModel.shared.evict(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // Switch instantly, like any Mac app's view switcher. No crossfades.
        Group {
            switch model.section {
            case .crap: ResultsView()
            case .apps: AppsView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $model.section) {
                    Text("Crap").tag(AppModel.Section.crap)
                        .help("Find and flush caches, junk and clutter (⌘1)")
                    Text("Apps").tag(AppModel.Section.apps)
                        .help("Uninstall apps along with everything they left behind (⌘2)")
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.evict(urls)
        } isTargeted: { model.dropTargeted = $0 }
    }
}

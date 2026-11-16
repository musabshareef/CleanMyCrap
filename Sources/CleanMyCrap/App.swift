import SwiftUI

@main
struct CleanMyCrapApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Clean My Crap") {
            RootView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 640)
                .tint(.teal)
        }
        .defaultSize(width: 1160, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .welcome: WelcomeView().transition(.blurReplace)
            case .scanning: ScanningView().transition(.blurReplace)
            case .results: ResultsView().transition(.opacity)
            case .cleaning: CleaningView().transition(.blurReplace)
            case .done: DoneView().transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.5), value: model.phase)
    }
}

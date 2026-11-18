import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle, set up the way its docs recommend for SwiftUI apps. Checks quietly in the background
/// and offers "Check for Updates…" in the app menu. Updates come from the appcast on GitHub Pages
/// and must be signed with our EdDSA key (SUPublicEDKey in Info.plist).
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published var canCheck = false

    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func check() { controller.checkForUpdates(nil) }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        Button("Check for Updates…") { updates.check() }
            .disabled(!updates.canCheck)
    }
}

/// Feedback goes to GitHub Issues: free, public, and the report arrives with the details we need.
enum Feedback {
    static let repo = URL(string: "https://github.com/musabshareef/CleanMyCrap")!

    static func send() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let body = """
        **What happened, or what would you like?**


        **Steps to reproduce (for bugs)**
        1.

        ---
        Clean My Crap \(version) · macOS \(os) · \(String(cString: machine))
        """
        var url = URLComponents(url: repo.appending(path: "issues/new"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "body", value: body)]
        if let u = url.url { NSWorkspace.shared.open(u) }
    }
}

import AppKit
import CrapCore

/// Links the bundled `crap` tool into /usr/local/bin, the way VS Code installs `code`.
@MainActor
enum CommandLineTool {
    static let link = URL(fileURLWithPath: "/usr/local/bin/crap")
    static var bundled: URL { Bundle.main.bundleURL.appending(path: "Contents/Helpers/crap") }

    static var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == bundled.path
    }

    static func install() async {
        guard FileManager.default.isExecutableFile(atPath: bundled.path) else {
            alert("No crap to install", "This build doesn't include the command-line tool. Build it with scripts/build-app.sh.")
            return
        }
        if isInstalled {
            alert("Already installed", "Type crap --help in Terminal to get started.")
            return
        }
        // /usr/local/bin belongs to root, so macOS asks for an admin password.
        let cmd = "/bin/mkdir -p /usr/local/bin && /bin/ln -sf \(shellQuoted(bundled.path)) /usr/local/bin/crap"
        let script = "do shell script \"\(cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with prompt \"Clean My Crap wants to install the crap command.\" with administrator privileges"
        _ = await Shell.run("/usr/bin/osascript", ["-e", script], timeout: 300)
        if isInstalled {
            alert("crap is installed", "Open Terminal and type crap --help. Agents can use it too: crap scan --json.")
        } else {
            alert("Didn't install", "Nothing changed. You can link it yourself:\nsudo ln -sf \"\(bundled.path)\" /usr/local/bin/crap")
        }
    }

    private static func shellQuoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

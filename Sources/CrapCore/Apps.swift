import AppKit
import Security

// MARK: - Installed apps

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    /// Every name the app might file its stuff under (file name, CFBundleName, executable…).
    public let aliases: Set<String>
    public let bundleID: String
    public let version: String?
    public let lastUsed: Date?
    public let added: Date?

    /// Not opened in this long means you forgot you had it.
    public static let forgottenAfter: TimeInterval = 180 * 86_400

    public var isForgotten: Bool {
        // Never opened counts too, as long as it's been sitting there a while.
        guard let reference = lastUsed ?? added else { return false }
        return reference < .now.addingTimeInterval(-Self.forgottenAfter)
    }

    public var lastUsedText: String {
        guard let lastUsed else { return "Never opened" }
        let ago = lastUsed.formatted(.relative(presentation: .named))
        return isForgotten ? "Last opened \(ago)" : "Opened \(ago)"
    }

    public init?(url: URL) {
        guard FS.isRealDir(url), let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier, !id.isEmpty else { return nil }
        let info = bundle.infoDictionary ?? [:]
        self.url = url
        name = url.deletingPathExtension().lastPathComponent
        bundleID = id
        version = info["CFBundleShortVersionString"] as? String
        aliases = Set([name, info["CFBundleName"], info["CFBundleDisplayName"], info["CFBundleExecutable"]]
            .compactMap { $0 as? String }
            .filter { $0.count >= 3 })
        lastUsed = MDItemCreateWithURL(nil, url as CFURL)
            .flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
        added = FS.addedDate(url)
    }
}

public enum AppInventory {
    public static let roots = [URL(fileURLWithPath: "/Applications"), FS.url("Applications")]

    /// Apps in /Applications and ~/Applications, one folder deep (Utilities, "Chrome Apps"…).
    public static func scan() -> [InstalledApp] {
        let own = Bundle.main.bundleIdentifier ?? "com.cleanmycrap.app"
        var out: [InstalledApp] = []
        func collect(_ dir: URL, depth: Int) {
            for child in FS.children(of: dir) {
                if child.pathExtension == "app" {
                    if let app = InstalledApp(url: child), app.bundleID != own { out.append(app) }
                } else if depth == 0, FS.isRealDir(child) {
                    collect(child, depth: 1)
                }
            }
        }
        roots.forEach { collect($0, depth: 0) }
        return out
    }
}

// MARK: - Leftovers of one app

public enum Leftovers {
    /// Where apps scatter their stuff in ~/Library, and what to call each place.
    public static let places: [(dir: String, kind: String, byName: Bool)] = [
        ("Application Support", "Application Support", true),
        ("Caches", "Cache", true),
        ("Logs", "Logs", true),
        ("Preferences", "Preferences", false),
        ("Preferences/ByHost", "Preferences", false),
        ("Saved Application State", "Window state", false),
        ("HTTPStorages", "Web storage", false),
        ("WebKit", "Web data", false),
        ("Cookies", "Cookies", false),
        ("Application Scripts", "Scripts", false),
        ("LaunchAgents", "Starts at login", false),
    ]

    public static let strippedExtensions: Set<String> = ["plist", "savedState", "binarycookies"]

    public static func find(for app: InstalledApp) async -> [Found] {
        let library = FS.url("Library")
        let signing = signingInfo(app.url)
        let names = Set(app.aliases.map { $0.lowercased() })
        var hits: [(url: URL, name: String, detail: String?)] = []

        for place in places {
            let dir = library.appending(path: place.dir)
            for child in FS.children(of: dir) {
                let n = child.lastPathComponent
                let ext = child.pathExtension
                let base = strippedExtensions.contains(ext) ? child.deletingPathExtension().lastPathComponent : n
                let byID = base == app.bundleID || base.hasPrefix(app.bundleID + ".")
                let byName = place.byName && names.contains(base.lowercased())
                if byID || byName { hits.append((child, n, "\(place.kind) · \(FS.pretty(dir))")) }
            }
        }

        // Sandboxed apps keep everything in a container. Sizing it without Full Disk Access
        // makes macOS ask about every app, so only peek at whether it's there.
        let fda = FS.hasFullDiskAccess
        var hidden: [Found] = []
        var shared = signing.groups.map { library.appending(path: "Group Containers/\($0)") }
        shared += FS.children(of: library.appending(path: "Group Containers"))
            .filter { $0.lastPathComponent.hasSuffix("." + app.bundleID) }
        let containers = [library.appending(path: "Containers/\(app.bundleID)")] + shared
        var seen = Set(hits.map(\.url.path))
        for url in containers where FS.exists(url) && seen.insert(url.path).inserted {
            let kind = url.path.contains("/Group Containers/") ? "Shared container" : "Container"
            if fda {
                hits.append((url, url.lastPathComponent, "\(kind) · \(FS.pretty(url.deletingLastPathComponent()))"))
            } else {
                hidden.append(Found(name: url.lastPathComponent,
                                    detail: "\(kind) · \(FS.pretty(url.deletingLastPathComponent()))",
                                    size: 0, removal: .trash(url)))
            }
        }

        return await FS.sized(hits, minSize: 0) { .trash($0) } + hidden
    }

    /// The app's team and the shared app-group containers it's entitled to.
    public static func signingInfo(_ url: URL) -> (team: String?, groups: [String]) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return (nil, []) }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return (nil, []) }
        let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return (dict[kSecCodeInfoTeamIdentifier as String] as? String,
                entitlements?["com.apple.security.application-groups"] as? [String] ?? [])
    }
}

// MARK: - Ghosts: leftovers of apps that are already gone

public enum Ghosts {
    public static let places: [(dir: String, kind: String)] = [
        ("Application Support", "Application Support"),
        ("Caches", "Cache"),
        ("Preferences", "Preferences"),
        ("Saved Application State", "Window state"),
        ("HTTPStorages", "Web storage"),
        ("WebKit", "Web data"),
        ("Logs", "Logs"),
        ("Cookies", "Cookies"),
        ("Application Scripts", "Scripts"),
    ]

    /// Reverse-DNS names that belong to tools and frameworks, not apps.
    public static let notApps = ["com.apple.", "group.", "org.swift.", "org.llvm.", "org.sparkle-project.",
                          "com.crashlytics", "io.sentry", "com.plausiblelabs.", "org.python.", "org.nodejs.",
                          "sh.brew", "org.homebrew", "com.google.keystone", "com.microsoft.autoupdate",
                          "com.bugsnag", "com.segment.", "com.tcltk.", "org.cups.", "org.webkit.",
                          "org.codehaus.", "com.cleanmycrap."]

    /// Something touched in the last two weeks is clearly still haunted by a living app.
    public static let quietFor: TimeInterval = 14 * 86_400

    nonisolated(unsafe) private static let reverseDNS = try! Regex(#"[a-z]{2,6}\.[A-Za-z0-9\-]+\.[A-Za-z0-9\-_.]+"#)

    public static func scan() async -> [Found] {
        let installed = AppInventory.scan().map { $0.bundleID.lowercased() }
        // Same vendor as something installed (com.microsoft.*): probably a helper, leave it.
        let vendors = Set(installed.map { $0.split(separator: ".").prefix(2).joined(separator: ".") })
        let library = FS.url("Library")
        var places = self.places.map { (library.appending(path: $0.dir), $0.kind) }
        if FS.hasFullDiskAccess { places.append((library.appending(path: "Containers"), "Container")) }

        var byID: [String: [(url: URL, kind: String)]] = [:]
        for (dir, kind) in places {
            for child in FS.children(of: dir) {
                let ext = child.pathExtension
                let id = Leftovers.strippedExtensions.contains(ext) ? child.deletingPathExtension().lastPathComponent
                                                                     : child.lastPathComponent
                guard id.wholeMatch(of: reverseDNS) != nil else { continue }
                byID[id, default: []].append((child, kind))
            }
        }

        let cutoff = Date.now.addingTimeInterval(-quietFor)
        var ghosts: [(id: String, urls: [URL], kinds: [String])] = []
        for (id, entries) in byID {
            let lower = id.lowercased()
            let vendor = lower.split(separator: ".").prefix(2).joined(separator: ".")
            guard !notApps.contains(where: { lower.hasPrefix($0) }),
                  !vendors.contains(vendor),
                  !installed.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") || $0.hasPrefix(lower + ".") }),
                  NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil,
                  entries.allSatisfy({ modified($0.url) < cutoff })
            else { continue }
            let kinds = entries.map(\.kind).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            ghosts.append((id, entries.map(\.url), kinds))
        }

        return await withTaskGroup(of: Found.self) { group in
            for g in ghosts {
                group.addTask {
                    let size = g.urls.reduce(Int64(0)) { $0 + FS.size(of: $1) }
                    return Found(name: g.id, detail: g.kinds.joined(separator: " · "), size: size,
                                 removal: g.urls.count == 1 ? .trash(g.urls[0]) : .trashAll(g.urls))
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
    }

    /// Newest modification date of a leftover (a folder's own date changes when its contents do).
    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

// MARK: - Eviction

public enum Evictor {
    public struct Outcome: Sendable {
        public var freed: Int64 = 0
        public var failures: [String] = []
        public var appGone = false
    }

    public static func evict(app: InstalledApp, items: [Found]) async -> Outcome {
        var outcome = Outcome()
        for item in items {
            guard let url = item.removal.url else { continue }
            if url == app.url {
                if await trashApp(url) {
                    outcome.freed += item.size
                    outcome.appGone = true
                } else {
                    outcome.failures.append("\(item.name): macOS wouldn't let it go.")
                }
            } else if isLibraryItem(url) {
                do {
                    try await Task.detached { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }.value
                    outcome.freed += item.size
                } catch {
                    outcome.failures.append("\(item.name): locked or protected.")
                }
            }
        }
        return outcome
    }

    /// Apps installed for every user (App Store apps, most .pkg installs) belong to root,
    /// so moving those needs an admin password. macOS asks for it, not us.
    private static func trashApp(_ url: URL) async -> Bool {
        let moved = await Task.detached { (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil }.value
        if moved || !FS.exists(url) { return true }

        let trash = FS.url(".Trash")
        var dest = trash.appending(path: url.lastPathComponent)
        if FS.exists(dest) {
            let stamp = Date.now.formatted(.dateTime.hour().minute().second()).replacingOccurrences(of: ":", with: ".")
            dest = trash.appending(path: "\(url.deletingPathExtension().lastPathComponent) \(stamp).app")
        }
        let script = "do shell script \"/bin/mv \" & quoted form of \(appleScriptString(url.path)) & \" \" & quoted form of \(appleScriptString(dest.path)) with prompt \"Clean My Crap wants to move \(appleScriptEscaped(url.deletingPathExtension().lastPathComponent)) to the Trash.\" with administrator privileges"
        _ = await Shell.run("/usr/bin/osascript", ["-e", script], timeout: 600)
        return !FS.exists(url)
    }

    private static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func appleScriptString(_ s: String) -> String { "\"\(appleScriptEscaped(s))\"" }

    /// Leftovers must live inside ~/Library, never the Library folder itself or one of its top-level folders.
    private static func isLibraryItem(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let library = FS.url("Library").standardizedFileURL.path
        guard path.hasPrefix(library + "/") else { return false }
        return path.dropFirst(library.count).split(separator: "/").count >= 2
    }
}

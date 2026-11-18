import AppKit
import CrapCore
import Foundation

/// Same version as the app it ships in: read from the enclosing app's Info.plist (Contents/Helpers/crap → Contents/Info.plist).
let version: String = {
    let exe = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    let info = exe.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Info.plist")
    return (NSDictionary(contentsOf: info)?["CFBundleShortVersionString"] as? String) ?? "1.1 (dev)"
}()

let usage = """
crap: find and flush the crap on your Mac. The command-line side of Clean My Crap.

USAGE
  crap <command> [options]

COMMANDS
  status                         Disk space, used and free
  scan                           Find crap. Lists categories; add --items for every item and its ID
      --risk safe,low,high         Only these risk levels
      --category <id>[,<id>…]      Only these categories (IDs from `crap scan`)
      --items                      List every item with its ID
  ghosts                         Leftovers of apps you already deleted (same as scan --category ghosts --items)
  flush <id>… [--safe]           Remove items or whole categories by ID. A dry run unless you pass --yes
      --safe                       Everything in the Safe categories
      --yes                        Actually do it
      --include-high-risk          Required to touch anything High Risk
  apps                           Installed apps, when you last opened them, and their size
      --forgotten                  Only apps not opened in six months
      --sort name|size|last-opened
  leftovers <app>                What an app has scattered around your Mac (name, bundle ID or path)
  evict <app>                    Move an app and its leftovers to the Trash. A dry run unless you pass --yes
      --keep-app                   Only the leftovers, leave the app
      --quit                       Quit the app first if it's running
      --yes                        Actually do it

GLOBAL OPTIONS
  --json                         Machine-readable output (for scripts and agents)
  --help, --version

SAFETY
  Nothing is removed without --yes. Safe and Low Risk items are deleted (they grow back);
  High Risk items, ghosts, apps and their leftovers go to the Trash. Item IDs come from a scan
  and are checked against a fresh one, so crap only ever removes what it would have found itself.

EXIT CODES
  0 ok · 1 something failed · 2 bad usage or refused (missing --include-high-risk, app running…)
"""

// MARK: - Arguments

struct Args {
    var command: String?
    var positional: [String] = []
    var flags: Set<String> = []
    var options: [String: String] = [:]

    static let valued: Set<String> = ["risk", "category", "sort"]

    init(_ argv: [String]) {
        var rest = argv[...]
        while let arg = rest.popFirst() {
            if arg.hasPrefix("--") {
                let body = String(arg.dropFirst(2))
                if let eq = body.firstIndex(of: "=") {
                    options[String(body[..<eq])] = String(body[body.index(after: eq)...])
                } else if Self.valued.contains(body), let value = rest.popFirst() {
                    options[body] = value
                } else {
                    flags.insert(body)
                }
            } else if arg == "-h" {
                flags.insert("help")
            } else if command == nil {
                command = arg
            } else {
                positional.append(arg)
            }
        }
    }

    var json: Bool { flags.contains("json") }
    func list(_ key: String) -> [String] {
        options[key]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
    }
}

struct Failure: Error {
    var message: String
    var code: Int32 = 1
}

// MARK: - Output

enum Out {
    static func json(_ value: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        print(String(decoding: data, as: UTF8.self))
    }

    static func err(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    /// Progress on stderr, only when a human is watching.
    static func progress(_ s: String) {
        guard isatty(STDERR_FILENO) != 0 else { return }
        FileHandle.standardError.write(Data("\r\u{1B}[K\(s)".utf8))
    }

    static func clearProgress() { progress("") }

    static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? String(s.prefix(width - 1)) + "…" : s + String(repeating: " ", count: width - s.count)
    }

    static func lpad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }

    static let iso = ISO8601DateFormatter()
}

func removalKind(_ r: Removal) -> String {
    switch r {
    case .delete: "delete"
    case .trash, .trashAll: "trash"
    case .commands: "command"
    }
}

func hiddenSize(_ item: ScannedItem) -> Bool { item.size == 0 && (item.removal.url?.path.contains("Containers/") ?? false) }
func hiddenSize(_ found: Found) -> Bool { found.size == 0 && (found.removal.url?.path.contains("Containers/") ?? false) }

func itemJSON(_ i: ScannedItem) -> [String: Any] {
    var d: [String: Any] = ["id": i.id, "name": i.name, "size": i.size, "action": removalKind(i.removal),
                            "paths": i.removal.urls.map(\.path)]
    if let detail = i.detail { d["detail"] = detail }
    return d
}

func foundJSON(_ f: Found) -> [String: Any] {
    var d: [String: Any] = ["name": f.name, "size": f.size, "action": removalKind(f.removal), "paths": f.removal.urls.map(\.path)]
    if let detail = f.detail { d["detail"] = detail }
    if hiddenSize(f) { d["sizeHidden"] = true }
    return d
}

func categoryJSON(_ c: ScannedCategory) -> [String: Any] {
    var d: [String: Any] = ["id": c.id, "name": c.rule.name, "risk": c.rule.risk.key, "explanation": c.rule.explanation,
                            "total": c.total, "items": c.items.map(itemJSON)]
    if let note = c.rule.note { d["note"] = note }
    return d
}

// MARK: - Commands

func status(_ a: Args) {
    let d = DiskInfo.current()
    if a.json {
        Out.json(["total": d.total, "free": d.free, "used": d.used, "usedFraction": (d.usedFraction * 1000).rounded() / 1000])
    } else {
        print("Macintosh HD: \(d.free.bytes) free of \(d.total.bytes) (\(Int(d.usedFraction * 100))% used)")
    }
}

func selectedRules(_ a: Args) throws -> [Rule] {
    var rules = Rules.all
    let risks = try a.list("risk").map { k -> Risk in
        guard let r = Risk(key: k) else { throw Failure(message: "Unknown risk '\(k)'. Use safe, low or high.", code: 2) }
        return r
    }
    if !risks.isEmpty { rules = rules.filter { risks.contains($0.risk) } }
    let ids = a.list("category")
    if !ids.isEmpty {
        let known = Set(Rules.all.map(\.id))
        if let bad = ids.first(where: { !known.contains($0) }) {
            throw Failure(message: "Unknown category '\(bad)'. Categories: \(Rules.all.map(\.id).joined(separator: ", "))", code: 2)
        }
        rules = rules.filter { ids.contains($0.id) }
    }
    return rules
}

func runScan(_ rules: [Rule]) async -> [ScannedCategory] {
    let result = await Scanner.scan(rules) { done, total in Out.progress("Sniffing… \(done)/\(total)") }
    Out.clearProgress()
    return result
}

func scan(_ a: Args, forceItems: Bool = false) async throws {
    let cats = await runScan(try selectedRules(a))
    let total = cats.reduce(Int64(0)) { $0 + $1.total }
    let fda = FS.hasFullDiskAccess

    if a.json {
        Out.json(["total": total, "categories": cats.map(categoryJSON), "fullDiskAccess": fda])
        return
    }
    if cats.isEmpty { print("No crap found. Suspiciously clean."); return }
    let showItems = forceItems || a.flags.contains("items")
    for risk in Risk.allCases {
        let group = cats.filter { $0.rule.risk == risk }
        guard !group.isEmpty else { continue }
        let sum = group.reduce(Int64(0)) { $0 + $1.total }
        print("\n\(risk.title) · \(risk.shortLabel) · \(sum.bytes)")
        for c in group {
            let count = c.items.count == 1 ? "1 item" : "\(c.items.count) items"
            print("  \(Out.pad(c.id, 18)) \(Out.pad(c.rule.name, 32)) \(Out.lpad(c.total.bytes, 10))   \(count)")
            if showItems {
                for i in c.items {
                    let size = hiddenSize(i) ? "?" : i.size.bytes
                    print("      \(i.id)  \(Out.lpad(size, 10))  \(i.name)\(i.detail.map { "  · \($0)" } ?? "")")
                }
            }
        }
    }
    print("\nTotal: \(total.bytes)")
    if !showItems { print("Add --items to see every item and its ID. Flush the safe stuff with: crap flush --safe") }
    if !fda { print("Some places need Full Disk Access (for the app running crap, e.g. your Terminal) to be checked.") }
}

func flush(_ a: Args) async throws {
    let safe = a.flags.contains("safe")
    guard safe || !a.positional.isEmpty else {
        throw Failure(message: "Tell me what to flush: item IDs or category IDs from `crap scan --items`, or --safe.", code: 2)
    }
    let known = Set(Rules.all.map(\.id))
    var ruleIDs = Set<String>()
    for arg in a.positional {
        let rule = String(arg.split(separator: ":").first ?? "")
        guard known.contains(rule) else { throw Failure(message: "Unknown category in '\(arg)'.", code: 2) }
        ruleIDs.insert(rule)
    }
    if safe { ruleIDs.formUnion(Rules.all.filter { $0.risk == .safe }.map(\.id)) }

    // Always against a fresh scan: an ID only works if crap would find that exact item right now.
    let cats = await runScan(Scanner.rules(withIDs: ruleIDs))
    var chosen: [(category: ScannedCategory, item: ScannedItem)] = []
    var seen = Set<String>()
    func take(_ c: ScannedCategory, _ i: ScannedItem) { if seen.insert(i.id).inserted { chosen.append((c, i)) } }
    var missing: [String] = []
    for arg in a.positional {
        if arg.contains(":") {
            if let c = cats.first(where: { $0.items.contains { $0.id == arg } }), let i = c.items.first(where: { $0.id == arg }) {
                take(c, i)
            } else { missing.append(arg) }
        } else if let c = cats.first(where: { $0.id == arg }) {
            c.items.forEach { take(c, $0) }
        }
    }
    if safe { for c in cats where c.rule.risk == .safe { c.items.forEach { take(c, $0) } } }

    if !missing.isEmpty {
        throw Failure(message: "Not found (already gone, or the scan doesn't find it anymore): \(missing.joined(separator: ", "))")
    }
    let risky = chosen.filter { $0.category.rule.risk == .high }
    if !risky.isEmpty && !a.flags.contains("include-high-risk") {
        throw Failure(message: "\(risky.count) of these are High Risk (\(Set(risky.map(\.category.rule.name)).sorted().joined(separator: ", "))). Look before you flush, then add --include-high-risk.", code: 2)
    }
    let total = chosen.reduce(Int64(0)) { $0 + $1.item.size }

    guard a.flags.contains("yes") else {
        if a.json {
            Out.json(["dryRun": true, "total": total, "items": chosen.map { itemJSON($0.item) }])
        } else if chosen.isEmpty {
            print("Nothing to flush.")
        } else {
            print("Would flush \(chosen.count) \(chosen.count == 1 ? "item" : "items") (\(total.bytes)):")
            for (c, i) in chosen {
                print("  \(i.id)  \(Out.lpad(i.size.bytes, 10))  \(i.name)  [\(removalKind(i.removal))\(c.rule.risk == .high ? ", high risk" : "")]")
            }
            print("\nNothing was touched. Run again with --yes to flush.")
        }
        return
    }

    var freed: Int64 = 0
    var results: [[String: Any]] = []
    var failed = 0
    for (n, (_, i)) in chosen.enumerated() {
        Out.progress("Flushing \(n + 1)/\(chosen.count): \(i.name)")
        let r = await Cleaner.remove(i.removal, size: i.size)
        freed += r.freed
        var d = itemJSON(i)
        d["freed"] = r.freed
        if let e = r.error { d["error"] = e; failed += 1 }
        results.append(d)
    }
    Out.clearProgress()
    if a.json {
        Out.json(["dryRun": false, "freed": freed, "items": results, "failed": failed])
    } else {
        for d in results where d["error"] != nil { print("  ✗ \(d["name"]!): \(d["error"]!)") }
        print("Flushed \(freed.bytes) across \(chosen.count - failed) \(chosen.count - failed == 1 ? "item" : "items").\(failed > 0 ? " \(failed) didn't fully flush." : "")")
        if chosen.contains(where: { $0.item.removal.isTrash }) { print("Some of it went to the Trash. Empty it to get that space back.") }
    }
    if failed > 0 { throw Failure(message: "", code: 1) }
}

// MARK: Apps

func allApps() async -> [InstalledApp] {
    await Task.detached { AppInventory.scan() }.value
}

func resolveApp(_ query: String) async throws -> InstalledApp {
    let expanded = (query as NSString).expandingTildeInPath
    if expanded.hasSuffix(".app"), FS.exists(URL(fileURLWithPath: expanded)) {
        guard let app = InstalledApp(url: URL(fileURLWithPath: expanded)) else {
            throw Failure(message: "\(query) doesn't look like an app.", code: 2)
        }
        return app
    }
    let apps = await allApps()
    let q = query.lowercased().replacingOccurrences(of: ".app", with: "")
    if let exact = apps.first(where: { $0.name.lowercased() == q || $0.bundleID.lowercased() == q }) { return exact }
    let partial = apps.filter { $0.name.lowercased().contains(q) }
    if partial.count == 1 { return partial[0] }
    if partial.isEmpty { throw Failure(message: "No app called '\(query)'. Try `crap apps`.", code: 2) }
    throw Failure(message: "'\(query)' matches several apps: \(partial.map(\.name).joined(separator: ", ")). Be more specific.", code: 2)
}

func appJSON(_ app: InstalledApp, size: Int64?) -> [String: Any] {
    var d: [String: Any] = ["name": app.name, "bundleID": app.bundleID, "path": app.url.path, "forgotten": app.isForgotten]
    if let v = app.version { d["version"] = v }
    if let l = app.lastUsed { d["lastOpened"] = Out.iso.string(from: l) }
    if let size { d["size"] = size }
    return d
}

func apps(_ a: Args) async throws {
    var list = await allApps()
    if a.flags.contains("forgotten") { list = list.filter(\.isForgotten) }
    Out.progress("Weighing \(list.count) apps…")
    let sizes: [String: Int64] = await withTaskGroup(of: (String, Int64).self) { g in
        for app in list { let url = app.url, id = app.id; g.addTask { (id, FS.size(of: url)) } }
        return await g.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
    Out.clearProgress()
    switch a.options["sort"] ?? "name" {
    case "size": list.sort { (sizes[$0.id] ?? 0) > (sizes[$1.id] ?? 0) }
    case "last-opened": list.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
    case "name": list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    case let other: throw Failure(message: "Unknown sort '\(other)'. Use name, size or last-opened.", code: 2)
    }
    if a.json { Out.json(["apps": list.map { appJSON($0, size: sizes[$0.id]) }]); return }
    if list.isEmpty {
        print(a.flags.contains("forgotten") ? "No forgotten apps. You've opened everything in the last six months. Respect." : "No apps found.")
        return
    }
    for app in list {
        let mark = app.isForgotten ? "💤 " : "   "
        print("\(mark)\(Out.pad(app.name, 30)) \(Out.pad(app.lastUsedText, 28)) \(Out.lpad((sizes[app.id] ?? 0).bytes, 10))   \(app.bundleID)")
    }
    let forgotten = list.filter(\.isForgotten).count
    if forgotten > 0 && !a.flags.contains("forgotten") { print("\n💤 \(forgotten) not opened in six months. See them with: crap apps --forgotten") }
}

func plan(for app: InstalledApp, keepApp: Bool) async -> [Found] {
    async let leftovers = Leftovers.find(for: app)
    var items: [Found] = []
    if !keepApp {
        let size = await Task.detached { FS.size(of: app.url) }.value
        items.append(Found(name: app.url.lastPathComponent, detail: "The app itself · \(FS.pretty(app.url.deletingLastPathComponent()))",
                           size: size, removal: .trash(app.url)))
    }
    return items + (await leftovers).sorted { $0.size > $1.size }
}

func printPlan(_ items: [Found]) {
    for f in items {
        let size = hiddenSize(f) ? "?" : f.size.bytes
        print("  \(Out.lpad(size, 10))  \(Out.pad(f.name, 44)) \(f.detail ?? "")")
    }
    if items.contains(where: hiddenSize) {
        print("  (? = macOS hides this container's size without Full Disk Access)")
    }
}

func leftovers(_ a: Args) async throws {
    guard let query = a.positional.first else { throw Failure(message: "Which app? e.g. crap leftovers Telegram", code: 2) }
    let app = try await resolveApp(query)
    let items = await plan(for: app, keepApp: true)
    let total = items.reduce(Int64(0)) { $0 + $1.size }
    if a.json {
        Out.json(["app": appJSON(app, size: nil), "total": total, "leftovers": items.map(foundJSON)])
        return
    }
    if items.isEmpty { print("\(app.name) keeps its crap to itself. No leftovers found."); return }
    print("\(app.name) (\(app.bundleID)) has \(items.count) \(items.count == 1 ? "leftover" : "leftovers"), \(total.bytes):")
    printPlan(items)
}

func evict(_ a: Args) async throws {
    guard let query = a.positional.first else { throw Failure(message: "Which app? e.g. crap evict Blender", code: 2) }
    let app = try await resolveApp(query)
    let keepApp = a.flags.contains("keep-app")
    let items = await plan(for: app, keepApp: keepApp)
    let total = items.reduce(Int64(0)) { $0 + $1.size }

    guard a.flags.contains("yes") else {
        if a.json {
            Out.json(["dryRun": true, "app": appJSON(app, size: nil), "total": total, "items": items.map(foundJSON)])
        } else {
            print(keepApp ? "Would move \(app.name)'s leftovers (\(total.bytes)) to the Trash:"
                          : "Would evict \(app.name) and its crap (\(total.bytes)) to the Trash:")
            printPlan(items)
            print("\nNothing was touched. Run again with --yes to evict.")
        }
        return
    }

    let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
    if !running.isEmpty {
        guard a.flags.contains("quit") else {
            throw Failure(message: "\(app.name) is still running. It can't move out while it's home. Quit it first, or add --quit.", code: 2)
        }
        running.forEach { $0.terminate() }
        for _ in 0..<40 where !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty else {
            throw Failure(message: "\(app.name) didn't quit (unsaved work?). Quit it yourself, then try again.")
        }
    }
    if !keepApp && !FileManager.default.isWritableFile(atPath: app.url.path) && !a.json {
        Out.err("\(app.name) was installed for everyone on this Mac, so macOS will ask for your password.")
    }

    let outcome = await Evictor.evict(app: app, items: items)
    if a.json {
        Out.json(["dryRun": false, "app": appJSON(app, size: nil), "freed": outcome.freed,
                  "appRemoved": outcome.appGone, "failures": outcome.failures])
    } else {
        if outcome.appGone { print("\(app.name) has left the building.") }
        print("\(outcome.freed.bytes) moved to the Trash. Empty it to actually get the space back.")
        outcome.failures.forEach { print("  ✗ \($0)") }
    }
    if !outcome.failures.isEmpty { throw Failure(message: "", code: 1) }
}

// MARK: - Main

@main
struct Crap {
    static func main() async {
        let a = Args(Array(CommandLine.arguments.dropFirst()))
        if a.flags.contains("version") { print("crap \(version)"); return }
        if a.flags.contains("help") || a.command == nil || a.command == "help" { print(usage); return }
        do {
            switch a.command! {
            case "status": status(a)
            case "scan": try await scan(a)
            case "ghosts":
                var g = a
                g.options["category"] = "ghosts"
                try await scan(g, forceItems: true)
            case "flush": try await flush(a)
            case "apps": try await apps(a)
            case "leftovers": try await leftovers(a)
            case "evict": try await evict(a)
            default: throw Failure(message: "Unknown command '\(a.command!)'. See crap --help.", code: 2)
            }
        } catch let f as Failure {
            Out.clearProgress()
            if !f.message.isEmpty {
                if a.json { Out.json(["error": f.message]) } else { Out.err("crap: \(f.message)") }
            }
            exit(f.code)
        } catch {
            Out.err("crap: \(error.localizedDescription)")
            exit(1)
        }
    }
}

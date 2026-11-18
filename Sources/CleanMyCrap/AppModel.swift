import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case welcome, scanning, results, cleaning }
    enum Section: String, Hashable { case crap, apps }

    /// One model for the whole app, so the Dock icon can hand over dropped apps.
    static let shared = AppModel()

    var section: Section = .crap
    let apps = AppsModel()
    var dropTargeted = false

    var phase: Phase = .welcome
    var disk = DiskInfo.current()

    // Scanning
    var categories: [CleanupCategory] = []
    var finishedRules: Set<String> = []
    var foundSoFar: Int64 = 0
    var needsFullDiskAccess = false

    // Cleaning
    var cleanProgress: Double = 0
    var cleanStatus = ""
    var report: CleanReport?
    /// The report sheet after a flush.
    var showReport = false

    var scanProgress: Double { Double(finishedRules.count) / Double(Rules.all.count) }
    var totalFound: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.selectedCount } }

    func categories(for risk: Risk) -> [CleanupCategory] { categories.filter { $0.risk == risk } }
    func total(for risk: Risk) -> Int64 { categories(for: risk).reduce(0) { $0 + $1.totalSize } }
    func selected(for risk: Risk) -> Int64 { categories(for: risk).reduce(0) { $0 + $1.selectedSize } }

    func select(_ risk: Risk, _ on: Bool) {
        withAnimation(.snappy) { categories(for: risk).forEach { $0.setAll(on) } }
    }

    func selectOnlySafe() {
        withAnimation(.snappy) { categories.forEach { $0.setAll($0.risk == .safe) } }
    }

    func selectAll(_ on: Bool) {
        withAnimation(.snappy) { categories.forEach { $0.setAll(on) } }
    }

    // MARK: Scan

    func scan() async {
        phase = .scanning
        categories = []
        finishedRules = []
        foundSoFar = 0
        report = nil
        disk = .current()
        Docker.reset()
        needsFullDiskAccess = !(await Task.detached { FS.canList(FS.url(".Trash")) }.value)

        await withTaskGroup(of: (Rule, [Found]).self) { group in
            for rule in Rules.all {
                group.addTask { (rule, await rule.scan()) }
            }
            for await (rule, items) in group {
                let category = CleanupCategory(rule: rule, found: items)
                withAnimation(.snappy) {
                    finishedRules.insert(rule.id)
                    foundSoFar += category.totalSize
                }
                // Show up in the sidebar as soon as they're found.
                if !category.items.isEmpty && category.totalSize >= rule.minTotal {
                    let at = categories.firstIndex { ($0.risk, -$0.totalSize) > (category.risk, -category.totalSize) }
                    withAnimation(.snappy) { categories.insert(category, at: at ?? categories.endIndex) }
                }
            }
        }
        phase = .results
    }

    // MARK: Flush

    func flush() async {
        let work = categories.flatMap { c in c.items.filter(\.isSelected).map { (category: c, item: $0) } }
        guard !work.isEmpty else { return }
        let before = DiskInfo.current().free
        phase = .cleaning
        cleanProgress = 0

        var freed: Int64 = 0
        var flushed: Set<CleanupItem.ID> = []
        var failures: [CleanReport.Failure] = []
        var movedToTrash = false
        var touchedDocker = false

        for (i, entry) in work.enumerated() {
            cleanStatus = entry.item.name
            let result = await Cleaner.remove(entry.item)
            freed += result.freed
            if result.freed > 0, entry.item.removal.isTrash { movedToTrash = true }
            if entry.category.id.hasPrefix("docker") { touchedDocker = true }
            if let error = result.error {
                failures.append(.init(name: entry.item.name, reason: error))
            } else {
                flushed.insert(entry.item.id)
            }
            withAnimation(.smooth) { cleanProgress = Double(i + 1) / Double(work.count) }
        }

        disk = .current()
        report = CleanReport(freed: freed, itemCount: work.count, freeBefore: before, freeAfter: disk.free,
                             failures: failures, movedToTrash: movedToTrash, touchedDocker: touchedDocker)
        try? await Task.sleep(for: .milliseconds(400))
        // What's gone is gone from the list too.
        for c in categories { c.items.removeAll { flushed.contains($0.id) } }
        categories.removeAll { $0.items.isEmpty }
        phase = .results
        showReport = true
    }

    /// Apps dragged onto the window or the Dock icon: off to the Apps side.
    func evict(_ urls: [URL]) -> Bool {
        guard let app = urls.first(where: { $0.pathExtension == "app" }) else { return false }
        section = .apps
        Task {
            await apps.loadIfNeeded()
            apps.open(app)
        }
        return true
    }

}

enum Cleaner {
    struct Result { var freed: Int64; var error: String? }

    static func remove(_ item: CleanupItem) async -> Result {
        await Task.detached(priority: .userInitiated) {
            switch item.removal {
            case .delete, .trash, .trashAll:
                let urls = item.removal.urls
                guard urls.allSatisfy(isSafeTarget) else { return Result(freed: 0, error: "Refused: outside your home folder") }
                var failure: String?
                for url in urls {
                    do {
                        if item.removal.isTrash {
                            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        } else {
                            try FileManager.default.removeItem(at: url)
                        }
                    } catch {
                        failure = "Some files were locked or protected, so part of it stayed."
                    }
                }
                let left = urls.reduce(Int64(0)) { $0 + (FS.exists($1) ? FS.size(of: $1) : 0) }
                return Result(freed: max(item.size - left, 0), error: failure)

            case .commands(let commands):
                for c in commands {
                    let r = await Shell.run(c.executable, c.arguments)
                    if r.status != 0 && !c.allowFailure {
                        let line = r.output.split(separator: "\n").last.map(String.init) ?? "exit \(r.status)"
                        return Result(freed: 0, error: line)
                    }
                }
                return Result(freed: item.size, error: nil)
            }
        }.value
    }

    /// Never touch anything outside the home folder, or the home folder's top level itself.
    private static func isSafeTarget(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = FS.home.standardizedFileURL.path
        guard path.hasPrefix(home + "/") else { return false }
        let depth = path.dropFirst(home.count).split(separator: "/").count
        return depth >= 2
    }
}

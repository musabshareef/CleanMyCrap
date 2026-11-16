import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case welcome, scanning, results, cleaning, done }

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

        let started = Date()
        var found: [CleanupCategory] = []
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
                if category.totalSize >= FS.oneMB { found.append(category) }
            }
        }

        // Let the scan screen breathe for a moment, even on a fast Mac.
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 1.5 { try? await Task.sleep(for: .seconds(1.5 - elapsed)) }

        categories = found.sorted { ($0.risk, -$0.totalSize) < ($1.risk, -$1.totalSize) }
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
            }
            withAnimation(.smooth) { cleanProgress = Double(i + 1) / Double(work.count) }
        }

        disk = .current()
        report = CleanReport(freed: freed, itemCount: work.count, freeBefore: before, freeAfter: disk.free,
                             failures: failures, movedToTrash: movedToTrash, touchedDocker: touchedDocker)
        try? await Task.sleep(for: .milliseconds(600))
        phase = .done
    }

    func startOver() {
        categories = []
        disk = .current()
        phase = .welcome
    }
}

enum Cleaner {
    struct Result { var freed: Int64; var error: String? }

    static func remove(_ item: CleanupItem) async -> Result {
        await Task.detached(priority: .userInitiated) {
            switch item.removal {
            case .delete(let url), .trash(let url):
                guard isSafeTarget(url) else { return Result(freed: 0, error: "Refused: outside your home folder") }
                var failure: String?
                do {
                    if case .trash = item.removal {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    } else {
                        try FileManager.default.removeItem(at: url)
                    }
                } catch {
                    failure = "Some files were locked or protected, so part of it stayed."
                }
                let left = FS.exists(url) ? FS.size(of: url) : 0
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

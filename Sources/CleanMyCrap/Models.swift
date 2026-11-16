import SwiftUI

// MARK: - Risk

enum Risk: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case safe, low, high

    var id: Int { rawValue }
    static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .safe: "Definitely Crap"
        case .low: "Probably Crap"
        case .high: "Might Be Treasure"
        }
    }

    var shortLabel: String {
        switch self {
        case .safe: "Safe"
        case .low: "Low Risk"
        case .high: "High Risk"
        }
    }

    var blurb: String {
        switch self {
        case .safe: "Grows back on its own. Nobody will miss it, least of all you."
        case .low: "Comes back when needed, but your next build or download will be slower."
        case .high: "Could be something you care about. Look before you flush."
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.seal.fill"
        case .low: "exclamationmark.circle.fill"
        case .high: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .low: .orange
        case .high: .red
        }
    }
}

// MARK: - Removal

struct Command: Sendable, Hashable {
    var executable: String
    var arguments: [String]
    var allowFailure = false
}

enum Removal: Sendable, Hashable {
    /// Permanently delete. Used for stuff that regenerates.
    case delete(URL)
    /// Move to the Trash. Used for high-risk stuff, so it can be fished back out.
    case trash(URL)
    /// Run tool commands (Docker, simctl…).
    case commands([Command])

    var url: URL? {
        switch self {
        case .delete(let u), .trash(let u): u
        case .commands: nil
        }
    }

    var isTrash: Bool { if case .trash = self { true } else { false } }
}

/// What a scan rule hands back. Sendable so rules can run off the main actor.
struct Found: Sendable {
    var name: String
    var detail: String?
    var size: Int64
    var removal: Removal
}

struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var detail: String?
    var size: Int64
    var removal: Removal
    var isSelected: Bool
}

@Observable
final class CleanupCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let risk: Risk
    let explanation: String
    let note: String?
    var items: [CleanupItem]

    init(rule: Rule, found: [Found]) {
        id = rule.id
        name = rule.name
        icon = rule.icon
        risk = rule.risk
        explanation = rule.explanation
        note = rule.note
        items = found
            .sorted { $0.size > $1.size }
            .map { CleanupItem(name: $0.name, detail: $0.detail, size: $0.size, removal: $0.removal,
                               isSelected: rule.risk == .safe) }
    }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.reduce(0) { $0 + ($1.isSelected ? $1.size : 0) } }
    var selectedCount: Int { items.lazy.filter(\.isSelected).count }
    var allSelected: Bool { items.allSatisfy(\.isSelected) }

    func setAll(_ on: Bool) {
        for i in items.indices { items[i].isSelected = on }
    }
}

struct Rule: Sendable {
    let id: String
    let name: String
    let icon: String
    let risk: Risk
    let explanation: String
    var note: String? = nil
    let scan: @Sendable () async -> [Found]
}

// MARK: - Disk

struct DiskInfo: Equatable {
    var total: Int64
    var free: Int64

    var used: Int64 { max(total - free, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                  .volumeAvailableCapacityForImportantUsageKey])
        return DiskInfo(total: Int64(v?.volumeTotalCapacity ?? 0),
                        free: v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

struct CleanReport {
    struct Failure: Identifiable { let id = UUID(); var name: String; var reason: String }
    var freed: Int64
    var itemCount: Int
    var freeBefore: Int64
    var freeAfter: Int64
    var failures: [Failure]
    var movedToTrash: Bool
    var touchedDocker: Bool
}

extension Int64 {
    var bytes: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: self)
    }
}

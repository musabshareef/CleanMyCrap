import Foundation

// MARK: - Risk

public enum Risk: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case safe, low, high

    public var id: Int { rawValue }
    public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .safe: "Definitely Crap"
        case .low: "Probably Crap"
        case .high: "Might Be Treasure"
        }
    }

    public var shortLabel: String {
        switch self {
        case .safe: "Safe"
        case .low: "Low Risk"
        case .high: "High Risk"
        }
    }

    public var blurb: String {
        switch self {
        case .safe: "Grows back on its own. Nobody will miss it, least of all you."
        case .low: "Comes back when needed, but your next build or download will be slower."
        case .high: "Could be something you care about. Look before you flush."
        }
    }

    public var symbol: String {
        switch self {
        case .safe: "checkmark.seal.fill"
        case .low: "exclamationmark.circle.fill"
        case .high: "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Removal

public struct Command: Sendable, Hashable {
    public var executable: String
    public var arguments: [String]
    public var allowFailure = false
}

public enum Removal: Sendable, Hashable {
    /// Permanently delete. Used for stuff that regenerates.
    case delete(URL)
    /// Move to the Trash. Used for high-risk stuff, so it can be fished back out.
    case trash(URL)
    /// Move several places to the Trash as one item (an old app's scattered leftovers).
    case trashAll([URL])
    /// Run tool commands (Docker, simctl…).
    case commands([Command])

    public var url: URL? { urls.first }

    public var urls: [URL] {
        switch self {
        case .delete(let u), .trash(let u): [u]
        case .trashAll(let us): us
        case .commands: []
        }
    }

    public var isTrash: Bool {
        switch self {
        case .trash, .trashAll: true
        default: false
        }
    }
}

/// What a scan rule hands back. Sendable so rules can run off the main actor.
public struct Found: Sendable {
    public var name: String
    public var detail: String?
    public var size: Int64
    public var removal: Removal

    public init(name: String, detail: String?, size: Int64, removal: Removal) {
        self.name = name; self.detail = detail; self.size = size; self.removal = removal
    }
}

public struct Rule: Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let risk: Risk
    public let explanation: String
    public var note: String? = nil
    /// Categories smaller than this stay hidden.
    public var minTotal: Int64 = 1 << 20
    public let scan: @Sendable () async -> [Found]
}

// MARK: - Disk

public struct DiskInfo: Equatable {
    public var total: Int64
    public var free: Int64

    public var used: Int64 { max(total - free, 0) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public static func current() -> DiskInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                  .volumeAvailableCapacityForImportantUsageKey])
        return DiskInfo(total: Int64(v?.volumeTotalCapacity ?? 0),
                        free: v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

extension Int64 {
    public var bytes: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: self)
    }
}

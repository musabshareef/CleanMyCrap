import CryptoKit
import Foundation

/// One thing that can be flushed, with an ID that stays the same between runs.
public struct ScannedItem: Sendable {
    /// "<category>:<8 hex>", derived from what the item points at, so a later run can find it again.
    public let id: String
    public let name: String
    public let detail: String?
    public let size: Int64
    public let removal: Removal
}

public struct ScannedCategory: Sendable {
    public let rule: Rule
    public let items: [ScannedItem]

    public var id: String { rule.id }
    public var total: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Runs the rules and hands back categories with stable item IDs. Used by the CLI (and anything else
/// that needs to scan now and act on the result later, by ID).
public enum Scanner {
    public static func rules(withIDs ids: Set<String>) -> [Rule] {
        Rules.all.filter { ids.contains($0.id) }
    }

    public static func scan(_ rules: [Rule] = Rules.all,
                            progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) async -> [ScannedCategory] {
        Docker.reset()
        var out: [ScannedCategory] = []
        await withTaskGroup(of: (Rule, [Found]).self) { group in
            for rule in rules { group.addTask { (rule, await rule.scan()) } }
            var done = 0
            for await (rule, found) in group {
                done += 1
                progress?(done, rules.count)
                let items = found
                    .sorted { $0.size > $1.size }
                    .map { ScannedItem(id: itemID(rule: rule.id, found: $0), name: $0.name, detail: $0.detail,
                                       size: $0.size, removal: $0.removal) }
                let category = ScannedCategory(rule: rule, items: items)
                if !items.isEmpty && category.total >= rule.minTotal { out.append(category) }
            }
        }
        return out.sorted { ($0.rule.risk, -$0.total) < ($1.rule.risk, -$1.total) }
    }

    public static func itemID(rule: String, found: Found) -> String {
        let key: String
        switch found.removal {
        case .delete, .trash, .trashAll:
            key = found.removal.urls.map(\.standardizedFileURL.path).joined(separator: "\n")
        case .commands(let commands):
            key = found.name + "\n" + commands.map { ([$0.executable] + $0.arguments).joined(separator: " ") }.joined(separator: "\n")
        }
        let digest = SHA256.hash(data: Data(key.utf8))
        return rule + ":" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

extension Risk {
    /// "safe", "low", "high": how the CLI and agents spell it.
    public var key: String {
        switch self {
        case .safe: "safe"
        case .low: "low"
        case .high: "high"
        }
    }

    public init?(key: String) {
        switch key.lowercased() {
        case "safe": self = .safe
        case "low": self = .low
        case "high": self = .high
        default: return nil
        }
    }
}

import SwiftUI
import CrapCore

extension Risk {
    var color: Color {
        switch self {
        case .safe: .green
        case .low: .orange
        case .high: .red
        }
    }
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

    func set(_ ids: Set<CleanupItem.ID>, _ on: Bool) {
        for i in items.indices where ids.contains(items[i].id) { items[i].isSelected = on }
    }

    func binding(for id: CleanupItem.ID) -> Binding<Bool> {
        Binding(
            get: { self.items.first { $0.id == id }?.isSelected ?? false },
            set: { on in self.set([id], on) }
        )
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


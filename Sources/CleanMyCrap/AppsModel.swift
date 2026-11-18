import AppKit
import SwiftUI

/// The Apps side: everything installed, how long since you used it, and evicting it with its crap.
@MainActor
@Observable
final class AppsModel {
    enum Filter: Hashable { case all, forgotten }
    enum Sort: String, CaseIterable, Identifiable {
        case name = "Name", size = "Size", lastOpened = "Last Opened"
        var id: Self { self }
    }

    var apps: [InstalledApp] = []
    var sizes: [InstalledApp.ID: Int64] = [:]
    /// A plain cache: filling it while rows draw must not redraw every row.
    @ObservationIgnored private var icons: [InstalledApp.ID: NSImage] = [:]
    var loading = false
    private var loaded = false

    var selection: InstalledApp.ID? {
        didSet { if let selection, let app = apps.first(where: { $0.id == selection }) { prepare(app) } }
    }
    var filter: Filter = .all
    var sort: Sort = .name
    var search = ""
    var plans: [InstalledApp.ID: EvictionPlan] = [:]

    var forgottenCount: Int { apps.lazy.filter(\.isForgotten).count }

    var visible: [InstalledApp] {
        var list = filter == .forgotten ? apps.filter(\.isForgotten) : apps
        if !search.isEmpty {
            list = list.filter { $0.name.localizedStandardContains(search) || $0.bundleID.localizedStandardContains(search) }
        }
        switch sort {
        case .name:
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            list.sort { (sizes[$0.id] ?? -1) > (sizes[$1.id] ?? -1) }
        case .lastOpened:
            list.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
        return list
    }

    func icon(for app: InstalledApp) -> NSImage {
        if let cached = icons[app.id] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        icons[app.id] = image
        return image
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        await reload()
    }

    func reload() async {
        loaded = true
        loading = true
        let found = await Task.detached { AppInventory.scan() }.value
        // Keep anything dropped in from elsewhere (Downloads, a disk image…) that still exists.
        let extras = apps.filter { a in !found.contains { $0.id == a.id } && FS.exists(a.url) }
        apps = found + extras
        loading = false

        // Sizes trickle in; Xcode alone can take a few seconds.
        await withTaskGroup(of: (InstalledApp.ID, Int64).self) { group in
            for app in apps where sizes[app.id] == nil {
                let url = app.url, id = app.id
                group.addTask { (id, FS.size(of: url)) }
            }
            for await (id, size) in group { sizes[id] = size }
        }
    }

    /// An app dropped on the window or the Dock icon.
    func open(_ url: URL) {
        let url = url.standardizedFileURL
        guard let app = apps.first(where: { $0.url.standardizedFileURL == url }) ?? InstalledApp(url: url) else { return }
        if !apps.contains(where: { $0.id == app.id }) {
            apps.append(app)
            Task.detached { let s = FS.size(of: app.url); await MainActor.run { self.sizes[app.id] = s } }
        }
        filter = .all
        search = ""
        plans[app.id] = nil  // Look again, fresh.
        selection = app.id
    }

    private func prepare(_ app: InstalledApp) {
        // Already looked, and nothing's happened since: keep it.
        if let existing = plans[app.id], existing.outcome == nil { return }
        let plan = EvictionPlan(app: app)
        plans[app.id] = plan
        Task { await plan.find(appSize: sizes[app.id]) }
    }

    func evict(_ plan: EvictionPlan) async {
        await plan.evict()
        if plan.outcome?.appGone == true {
            withAnimation(.snappy) {
                apps.removeAll { $0.id == plan.app.id }
                sizes[plan.app.id] = nil
            }
        }
    }
}

@MainActor
@Observable
final class EvictionPlan {
    let app: InstalledApp
    var items: [CleanupItem] = []
    var finding = true
    var evicting = false
    var outcome: Evictor.Outcome?
    var isRunning = false

    init(app: InstalledApp) { self.app = app }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.reduce(0) { $0 + ($1.isSelected ? $1.size : 0) } }
    var selectedCount: Int { items.lazy.filter(\.isSelected).count }
    var leftoverCount: Int { max(items.count - 1, 0) }
    var appSelected: Bool { items.first { $0.removal.url == app.url }?.isSelected ?? false }

    func find(appSize: Int64?) async {
        finding = true
        let app = self.app
        async let leftovers = Leftovers.find(for: app)
        let size: Int64
        if let appSize { size = appSize } else { size = await Task.detached { FS.size(of: app.url) }.value }
        let bundle = CleanupItem(name: app.url.lastPathComponent, detail: "The app itself · \(FS.pretty(app.url.deletingLastPathComponent()))",
                                 size: size, removal: .trash(app.url), isSelected: true)
        let rest = await leftovers
            .sorted { $0.size > $1.size }
            .map { CleanupItem(name: $0.name, detail: $0.detail, size: $0.size, removal: $0.removal, isSelected: true) }
        withAnimation(.snappy) {
            items = [bundle] + rest
            finding = false
        }
        refreshRunning()
    }

    func refreshRunning() {
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    func quitApp() async {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.terminate() }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(250))
            refreshRunning()
            if !isRunning { return }
        }
    }

    func evict() async {
        refreshRunning()
        guard !isRunning else { return }
        evicting = true
        let chosen = items.filter(\.isSelected)
        let app = self.app
        let result = await Evictor.evict(app: app, items: chosen)
        withAnimation(.smooth) {
            outcome = result
            evicting = false
        }
    }

    func set(_ ids: Set<CleanupItem.ID>, _ on: Bool) {
        for i in items.indices where ids.contains(items[i].id) { items[i].isSelected = on }
    }

    func setAll(_ on: Bool) { for i in items.indices { items[i].isSelected = on } }

    func binding(for id: CleanupItem.ID) -> Binding<Bool> {
        Binding(get: { self.items.first { $0.id == id }?.isSelected ?? false },
                set: { self.set([id], $0) })
    }
}

import SwiftUI
import CrapCore

struct AppsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var apps = model.apps
        let plan = apps.selection.flatMap { apps.plans[$0] }

        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $apps.selection) {
                ForEach(apps.visible) { app in
                    AppRow(app: app).tag(app.id)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $apps.filter) {
                    Text("All Apps").tag(AppsModel.Filter.all)
                    Text("Forgotten (\(apps.forgottenCount))").tag(AppsModel.Filter.forgotten)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .overlay {
                if apps.loading && apps.apps.isEmpty {
                    ProgressView()
                } else if apps.visible.isEmpty {
                    if !apps.search.isEmpty {
                        ContentUnavailableView.search(text: apps.search)
                    } else if apps.filter == .forgotten {
                        ContentUnavailableView("Nothing Forgotten", systemImage: "moon.zzz",
                                               description: Text("You've opened every app in the last six months. Respect."))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            if let plan {
                EvictView(plan: plan)
                    .id(plan.app.id)
            } else {
                MoveOutPrompt()
            }
        }
        .searchable(text: $apps.search, placement: .toolbar, prompt: "Find an app")
        .navigationTitle(plan?.app.name ?? (apps.filter == .forgotten ? "Forgotten Apps" : "All Apps"))
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("Sort By", selection: $apps.sort) {
                        ForEach(AppsModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort apps")
                Button {
                    Task { await apps.reload() }
                } label: {
                    Label("Look Again", systemImage: "arrow.clockwise")
                }
                .help("Look for apps again")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                let size = canEvict(plan) ? plan?.selectedSize ?? 0 : 0
                Button { confirming = true } label: {
                    Label("Evict \(size > 0 ? size.bytes : "")", systemImage: "box.truck.fill")
                        .labelStyle(.titleAndIcon)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.accent)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!canEvict(plan))
                .help(plan?.isRunning == true ? "Quit the app first" : "Move the app and its crap to the Trash (⌘⌫)")
                .animation(.snappy, value: size)
            }
        }
        .alert(plan.map { "Evict \($0.app.name)?" } ?? "", isPresented: $confirming, presenting: plan) { plan in
            Button("Evict", role: .destructive) { Task { await apps.evict(plan) } }
            Button("Let It Stay", role: .cancel) {}
        } message: { plan in
            Text(confirmMessage(plan))
        }
        .task { await apps.loadIfNeeded() }
    }

    private var subtitle: String {
        let apps = model.apps
        let total = apps.apps.reduce(Int64(0)) { $0 + (apps.sizes[$1.id] ?? 0) }
        var parts = ["\(apps.apps.count) apps"]
        if total > 0 { parts.append(total.bytes) }
        if apps.forgottenCount > 0 { parts.append("\(apps.forgottenCount) forgotten") }
        return parts.joined(separator: " · ")
    }

    private func canEvict(_ plan: EvictionPlan?) -> Bool {
        guard let plan else { return false }
        return !plan.finding && !plan.evicting && plan.outcome == nil && !plan.isRunning && plan.selectedCount > 0
    }

    private func confirmMessage(_ plan: EvictionPlan) -> String {
        let leftovers = plan.items.filter { $0.isSelected && $0.removal.url != plan.app.url }.count
        let stuff = leftovers == 1 ? "1 leftover" : "\(leftovers) leftovers"
        var lines = [plan.appSelected
            ? "\(plan.app.name) and \(stuff) (\(plan.selectedSize.bytes)) go to the Trash."
            : "\(stuff.capitalized) (\(plan.selectedSize.bytes)) go to the Trash. The app itself stays."]
        lines.append("Changed your mind? Fish it all back out of the Trash.")
        if plan.appSelected && !FileManager.default.isWritableFile(atPath: plan.app.url.path) {
            lines.append("This app was installed for everyone on this Mac, so macOS will ask for your password.")
        }
        return lines.joined(separator: "\n\n")
    }
}

// MARK: - Sidebar row

struct AppRow: View {
    @Environment(AppModel.self) private var model
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.apps.icon(for: app))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                HStack(spacing: 3) {
                    if app.isForgotten { Image(systemName: "moon.zzz.fill") }
                    Text(app.lastUsedText)
                }
                .font(.caption)
                .foregroundStyle(app.isForgotten ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let size = model.apps.sizes[app.id] {
                Text(size.bytes)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Nothing selected

struct MoveOutPrompt: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let targeted = model.dropTargeted
        VStack(spacing: 18) {
            Image(systemName: "box.truck.fill")
                .font(.system(size: 64))
                .foregroundStyle(Brand.gradient)
                .symbolEffect(.bounce, value: targeted)
            VStack(spacing: 8) {
                Text("Moving out? Take your crap with you.")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Drop an app here, or pick one from the list. We'll find everything it left lying around your Mac and haul it all to the Trash.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            let forgotten = model.apps.forgottenCount
            if forgotten > 0 && model.apps.filter != .forgotten {
                Button {
                    withAnimation(.snappy) { model.apps.filter = .forgotten }
                } label: {
                    Label(forgotten == 1 ? "Show the app you forgot you had"
                                         : "Show the \(forgotten) apps you forgot you had",
                          systemImage: "moon.zzz.fill")
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(targeted ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: targeted ? 3 : 1.5, dash: [8, 6]))
                .background(targeted ? Brand.accent.opacity(0.06) : .clear,
                            in: .rect(cornerRadius: 24, style: .continuous))
                .padding(24)
        }
        .animation(.snappy, value: targeted)
    }
}

// MARK: - One app

struct EvictView: View {
    @Environment(AppModel.self) private var model
    @Bindable var plan: EvictionPlan
    @State private var highlighted = Set<CleanupItem.ID>()
    @State private var sortOrder = [KeyPathComparator(\CleanupItem.size, order: .reverse)]

    var body: some View {
        Group {
            if let outcome = plan.outcome {
                MovedOutView(plan: plan, outcome: outcome)
                    .transition(.blurReplace)
            } else {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                    if plan.finding {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Sniffing out what \(plan.app.name) left lying around…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        table
                    }
                }
                .overlay {
                    if plan.evicting {
                        ZStack {
                            Rectangle().fill(.background.opacity(0.7))
                            VStack(spacing: 14) {
                                Mascot(size: 96, mood: .flushing)
                                Text("Loading the truck…").font(.title3).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            plan.refreshRunning()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            plan.refreshRunning()
        }
    }

    private var header: some View {
        let app = plan.app
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: model.apps.icon(for: app))
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(app.name).font(.title2.weight(.bold))
                        if app.isForgotten {
                            Label("Gathering Dust", systemImage: "moon.zzz.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(.orange.opacity(0.14), in: .capsule)
                        }
                    }
                    Text([app.version.map { "Version \($0)" }, app.bundleID, app.lastUsedText]
                        .compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 20)
                if !plan.finding {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(plan.totalSize.bytes)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text(plan.leftoverCount == 1 ? "App + 1 leftover" : "App + \(plan.leftoverCount) leftovers")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if plan.isRunning {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk.departure")
                        .foregroundStyle(.orange)
                    Text("\(app.name) is still running. It can't move out while it's home.")
                    Spacer()
                    Button("Quit \(app.name)") { Task { await plan.quitApp() } }
                }
                .padding(12)
                .card(cornerRadius: 12)
            }

            if !plan.finding {
                HStack {
                    Text("\(plan.selectedSize.bytes) selected")
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    Button("Select All") { withAnimation(.snappy) { plan.setAll(true) } }
                        .disabled(plan.selectedCount == plan.items.count)
                    Button("Select None") { withAnimation(.snappy) { plan.setAll(false) } }
                        .disabled(plan.selectedCount == 0)
                }
            }
        }
    }

    private var table: some View {
        let rows = plan.items.sorted(using: sortOrder)
        let biggest = max(plan.items.map(\.size).max() ?? 1, 1)
        return Table(rows, selection: $highlighted, sortOrder: $sortOrder) {
            TableColumn("") { item in
                Toggle("", isOn: plan.binding(for: item.id))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(22)

            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    if item.removal.url == plan.app.url {
                        Image(nsImage: model.apps.icon(for: plan.app)).resizable().frame(width: 16, height: 16)
                    }
                    Text(item.name).lineLimit(1).help(item.name)
                }
            }
            .width(min: 160, ideal: 300)

            TableColumn("What & Where") { item in
                Text(item.detail ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 120, ideal: 300)

            TableColumn("Size", value: \.size) { item in
                HStack(spacing: 10) {
                    if item.size > 0 || !(item.removal.url?.path.contains("Containers/") ?? false) {
                        SizeBar(fraction: Double(item.size) / Double(biggest), color: Brand.accent)
                        Text(item.size.bytes)
                            .monospacedDigit()
                            .frame(minWidth: 64, alignment: .trailing)
                    } else {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.tertiary)
                            .help("macOS keeps this one's size private until you give Clean My Crap Full Disk Access.")
                    }
                }
            }
            .width(min: 150, ideal: 220)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.enabled)
        .contextMenu(forSelectionType: CleanupItem.ID.self) { ids in
            let targets = ids.isEmpty ? highlighted : ids
            Button("Evict It") { plan.set(targets, true) }
            Button("Let It Stay") { plan.set(targets, false) }
            let urls = urls(for: targets)
            if !urls.isEmpty {
                Divider()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(urls.map { $0.path(percentEncoded: false) }.joined(separator: "\n"), forType: .string)
                }
            }
        } primaryAction: { ids in
            let urls = urls(for: ids)
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
        .onKeyPress(.space) {
            guard !highlighted.isEmpty else { return .ignored }
            let allOn = plan.items.filter { highlighted.contains($0.id) }.allSatisfy(\.isSelected)
            plan.set(highlighted, !allOn)
            return .handled
        }
    }

    private func urls(for ids: Set<CleanupItem.ID>) -> [URL] {
        plan.items.filter { ids.contains($0.id) }.flatMap(\.removal.urls)
    }
}

// MARK: - After

struct MovedOutView: View {
    @Environment(AppModel.self) private var model
    let plan: EvictionPlan
    let outcome: Evictor.Outcome

    var body: some View {
        VStack(spacing: 20) {
            Mascot(size: 128, mood: outcome.failures.isEmpty ? .proud : .idle)
            VStack(spacing: 8) {
                Text(outcome.appGone ? "\(plan.app.name) has left the building." : "Leftovers hauled away.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("\(outcome.freed.bytes) of it is in the Trash. Empty the Trash to actually get the space back.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !outcome.failures.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("A few things refused to leave", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(outcome.failures, id: \.self) { Text($0).foregroundStyle(.secondary) }
                }
                .padding(16)
                .frame(maxWidth: 480, alignment: .leading)
                .card()
            }
            HStack(spacing: 12) {
                Button("Open Trash") { NSWorkspace.shared.open(FS.url(".Trash")) }
                Button("Evict Another") { model.apps.selection = nil }
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

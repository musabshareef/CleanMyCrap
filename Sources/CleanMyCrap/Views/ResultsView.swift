import SwiftUI
import CrapCore

enum SidebarItem: Hashable {
    case overview
    case category(String)
}

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .overview
    @State private var confirming = false
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $selection) {
                NavigationLink(value: SidebarItem.overview) {
                    Label("Overview", systemImage: "square.grid.2x2.fill")
                }
                ForEach(Risk.allCases) { risk in
                    let cats = model.categories(for: risk)
                    if !cats.isEmpty {
                        Section {
                            ForEach(cats) { c in
                                NavigationLink(value: SidebarItem.category(c.id)) {
                                    CategoryRow(category: c)
                                }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: risk.symbol)
                                    .foregroundStyle(risk.color)
                                Text(risk.title)
                                    .foregroundStyle(risk.color)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 360)
        } detail: {
            Group {
                switch selection {
                case .category(let id):
                    if let c = model.categories.first(where: { $0.id == id }) {
                        CategoryDetailView(category: c)
                    } else {
                        overview
                    }
                default:
                    overview
                }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Only the Safe Stuff") { model.selectOnlySafe() }
                    Button("Everything (YOLO)") { model.selectAll(true) }
                    Button("Nothing") { model.selectAll(false) }
                } label: {
                    Label("Select", systemImage: "checklist")
                }
                .disabled(model.phase != .results)
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Sniff Again", systemImage: "arrow.clockwise")
                }
                .help("Scan again (⌘R)")
                .disabled(model.phase == .scanning || model.phase == .cleaning)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                let size = model.selectedSize
                Button { confirming = true } label: {
                    Label("Flush \(size > 0 ? size.bytes : "")", systemImage: "drop.fill")
                        .labelStyle(.titleAndIcon)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .buttonStyle(.glassProminent)
                .tint(model.selected(for: .high) > 0 ? .red : Brand.accent)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(size == 0 || model.phase != .results)
                .help(size > 0 ? "Flush the selected crap (⌘⌫)" : "Select some crap first")
                .animation(.snappy, value: size)
            }
        }
        .sheet(isPresented: Binding(get: { model.phase == .cleaning || model.showReport },
                                    set: { if !$0 { model.showReport = false } })) {
            FlushSheet().environment(model)
        }
        .alert("Flush \(model.selectedSize.bytes) of crap?", isPresented: $confirming) {
            Button("Flush It", role: .destructive) { Task { await model.flush() } }
            Button("Not Yet", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    /// Where you are, not what the app is called (HIG: don't title windows with the app name).
    private var title: String {
        if case .category(let id) = selection, let c = model.categories.first(where: { $0.id == id }) { return c.name }
        return "Overview"
    }

    @ViewBuilder private var overview: some View {
        switch model.phase {
        case .welcome: WelcomePane()
        case .scanning: ScanPane()
        default: OverviewView(selection: $selection)
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .welcome: return "\(model.disk.free.bytes) free of \(model.disk.total.bytes)"
        case .scanning: return "Sniffing… \(model.foundSoFar.bytes) so far"
        default: break
        }
        let selected = model.selectedSize
        return selected > 0
            ? "\(selected.bytes) of \(model.totalFound.bytes) selected"
            : "\(model.totalFound.bytes) of crap found. Nothing selected."
    }

    private var confirmMessage: String {
        var lines: [String] = []
        let parts = Risk.allCases.compactMap { r -> String? in
            let s = model.selected(for: r)
            return s > 0 ? "\(r.shortLabel): \(s.bytes)" : nil
        }
        lines.append(parts.joined(separator: "  ·  "))
        lines.append("Safe and low-risk crap is deleted for good. It grows back on its own.")
        if model.categories.first(where: { $0.id == "ghosts" })?.selectedCount ?? 0 > 0 {
            lines.append("Ghosts of Apps Past go to the Trash instead, just in case.")
        }
        if model.selected(for: .high) > 0 {
            lines.append("High-risk files go to the Trash, so you can fish them back out. Docker volumes can't be undone.")
        }
        return lines.joined(separator: "\n\n")
    }
}

// MARK: - Sidebar row

struct CategoryRow: View {
    @Bindable var category: CleanupCategory

    var body: some View {
        HStack(spacing: 8) {
            Toggle(sources: $category.items, isOn: \.isSelected) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .fixedSize()
                .tint(category.risk.color)
            Image(systemName: category.icon)
                .foregroundStyle(category.risk.color)
                .frame(width: 20)
            Text(category.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(category.totalSize.bytes)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Copy.headline(for: model.totalFound))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("We found \(model.totalFound.bytes) you could get rid of. The safe stuff is already picked. The rest is up to you.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if model.needsFullDiskAccess {
                    FullDiskAccessBanner()
                }

                HStack(alignment: .top, spacing: 16) {
                    ForEach(Risk.allCases) { RiskCard(risk: $0) }
                }

                BiggestOffenders(selection: $selection)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RiskCard: View {
    @Environment(AppModel.self) private var model
    let risk: Risk

    var body: some View {
        let total = model.total(for: risk)
        let selected = model.selected(for: risk)
        let allOn = total > 0 && selected == total

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: risk.symbol)
                    .font(.title2)
                    .foregroundStyle(risk.color)
                Spacer()
                Text(risk.shortLabel.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(risk.color)
            }
            Text(risk.title)
                .font(.title3.weight(.bold))
            Text(risk.blurb)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(total.bytes)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack {
                Text(selected > 0 ? "\(selected.bytes) selected" : "Nothing selected")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                Button(allOn ? "Deselect" : "Select All") { model.select(risk, !allOn) }
                    .controlSize(.small)
                    .disabled(total == 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .card(cornerRadius: 20)
    }
}

struct BiggestOffenders: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?

    var body: some View {
        let top = model.categories
            .flatMap { c in c.items.map { (category: c, item: $0) } }
            .sorted { $0.item.size > $1.item.size }
            .prefix(8)
        let biggest = top.first?.item.size ?? 1

        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Biggest Offenders")
                    .font(.title2.weight(.bold))
                VStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.item.id) { index, entry in
                        Button {
                            selection = .category(entry.category.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.category.icon)
                                    .foregroundStyle(entry.category.risk.color)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.item.name).lineLimit(1)
                                    Text(entry.category.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(minWidth: 180, idealWidth: 300, maxWidth: 360, alignment: .leading)
                                SizeBar(fraction: Double(entry.item.size) / Double(biggest), color: entry.category.risk.color)
                                    .frame(minWidth: 80, maxWidth: .infinity)
                                Text(entry.item.size.bytes)
                                    .monospacedDigit()
                                    .frame(width: 80, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if index < top.count - 1 { Divider().padding(.leading, 50) }
                    }
                }
                .padding(.vertical, 4)
                .card()
            }
        }
    }
}

struct SizeBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color.gradient)
                    .frame(width: max(geo.size.width * min(fraction, 1), 4))
            }
        }
        .frame(height: 6)
    }
}

struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.title)
                .foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some crap is behind a locked door")
                    .font(.headline)
                Text("Give Clean My Crap Full Disk Access to sniff your Trash, Mail and Messages attachments, podcasts and device backups too, then scan again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(18)
        .card()
    }
}

// MARK: - Category detail

struct CategoryDetailView: View {
    @Bindable var category: CleanupCategory
    @State private var highlighted = Set<CleanupItem.ID>()
    @State private var sortOrder = [KeyPathComparator(\CleanupItem.size, order: .reverse)]

    var body: some View {
        let rows = category.items.sorted(using: sortOrder)
        let biggest = category.items.map(\.size).max() ?? 1

        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Table(rows, selection: $highlighted, sortOrder: $sortOrder) {
                TableColumn("") { item in
                    Toggle("", isOn: category.binding(for: item.id))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .tint(category.risk.color)
                }
                .width(22)

                TableColumn("Name", value: \.name) { item in
                    Text(item.name)
                        .lineLimit(1)
                        .help(item.name)
                }
                .width(min: 160, ideal: 280)

                TableColumn("Where") { item in
                    Text(item.detail ?? item.removal.url?.deletingLastPathComponent().path(percentEncoded: false) ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 120, ideal: 320)

                TableColumn("Size", value: \.size) { item in
                    HStack(spacing: 10) {
                        SizeBar(fraction: Double(item.size) / Double(biggest), color: category.risk.color)
                        Text(item.size.bytes)
                            .monospacedDigit()
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                }
                .width(min: 150, ideal: 220)
            }
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
            .contextMenu(forSelectionType: CleanupItem.ID.self) { ids in
                let targets = ids.isEmpty ? highlighted : ids
                Button("Select for Flushing") { category.set(targets, true) }
                Button("Don't Flush") { category.set(targets, false) }
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
                let allOn = category.items.filter { highlighted.contains($0.id) }.allSatisfy(\.isSelected)
                category.set(highlighted, !allOn)
                return .handled
            }
        }
        .onChange(of: category.id) { highlighted = [] }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: category.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(category.risk.color)
                    .frame(width: 44, height: 44)
                    .background(category.risk.color.opacity(0.12), in: .rect(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(category.name).font(.title2.weight(.bold))
                        RiskBadge(risk: category.risk)
                    }
                    Text(category.explanation)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 20)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(category.totalSize.bytes)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("\(category.items.count) \(category.items.count == 1 ? "item" : "items")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let note = category.note {
                Label(note, systemImage: "info.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(category.selectedSize.bytes) selected")
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Button("Select All") { withAnimation(.snappy) { category.setAll(true) } }
                    .disabled(category.allSelected)
                Button("Select None") { withAnimation(.snappy) { category.setAll(false) } }
                    .disabled(category.selectedCount == 0)
            }
        }
    }

    private func urls(for ids: Set<CleanupItem.ID>) -> [URL] {
        category.items.filter { ids.contains($0.id) }.flatMap(\.removal.urls)
    }
}

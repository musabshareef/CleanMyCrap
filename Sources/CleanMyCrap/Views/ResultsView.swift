import SwiftUI

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
                        OverviewView(selection: $selection)
                    }
                default:
                    OverviewView(selection: $selection)
                }
            }
            .safeAreaBar(edge: .bottom) {
                FlushBar { confirming = true }
            }
        }
        .navigationTitle("Clean My Crap")
        .navigationSubtitle("\(model.totalFound.bytes) of crap found")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Only the Safe Stuff") { model.selectOnlySafe() }
                    Button("Everything (YOLO)") { model.selectAll(true) }
                    Button("Nothing") { model.selectAll(false) }
                } label: {
                    Label("Select", systemImage: "checklist")
                }
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Sniff Again", systemImage: "arrow.clockwise")
                }
                .help("Scan again")
            }
        }
        .alert("Flush \(model.selectedSize.bytes) of crap?", isPresented: $confirming) {
            Button("Flush It", role: .destructive) { Task { await model.flush() } }
            Button("Not Yet", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        var lines: [String] = []
        let parts = Risk.allCases.compactMap { r -> String? in
            let s = model.selected(for: r)
            return s > 0 ? "\(r.shortLabel): \(s.bytes)" : nil
        }
        lines.append(parts.joined(separator: "  ·  "))
        lines.append("Safe and low-risk crap is deleted for good. It grows back on its own.")
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
            VStack(alignment: .leading, spacing: 28) {
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

                GlassEffectContainer(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Risk.allCases) { RiskCard(risk: $0) }
                    }
                }

                BiggestOffenders(selection: $selection)
            }
            .padding(32)
            .padding(.bottom, 20)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
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
                    .buttonStyle(.glass)
                    .tint(risk.color)
                    .controlSize(.small)
                    .disabled(total == 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .glassEffect(.regular.tint(risk.color.opacity(0.05)), in: .rect(cornerRadius: 26))
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
                                Spacer()
                                SizeBar(fraction: Double(entry.item.size) / Double(biggest), color: entry.category.risk.color)
                                    .frame(width: 140)
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
                .glassEffect(in: .rect(cornerRadius: 20))
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
                Text("Give Clean My Crap Full Disk Access to sniff your Trash and device backups too, then scan again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.glass)
        }
        .padding(18)
        .glassEffect(in: .rect(cornerRadius: 20))
    }
}

// MARK: - Category detail

struct CategoryDetailView: View {
    @Bindable var category: CleanupCategory

    var body: some View {
        let biggest = category.items.first?.size ?? 1
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: category.icon)
                        .font(.system(size: 30))
                        .foregroundStyle(category.risk.color)
                        .frame(width: 68, height: 68)
                        .glassEffect(.regular.tint(category.risk.color.opacity(0.14)), in: .rect(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(category.name).font(.largeTitle.weight(.bold))
                            RiskBadge(risk: category.risk)
                        }
                        Text(category.explanation)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(category.totalSize.bytes)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("\(category.items.count) \(category.items.count == 1 ? "item" : "items")")
                            .foregroundStyle(.secondary)
                    }
                }

                if let note = category.note {
                    Label(note, systemImage: "info.circle.fill")
                        .font(.callout)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(in: .rect(cornerRadius: 14))
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
                .buttonStyle(.glass)

                LazyVStack(spacing: 0) {
                    ForEach($category.items) { $item in
                        ItemRow(item: $item, fraction: Double(item.size) / Double(biggest), color: category.risk.color)
                        if item.id != category.items.last?.id { Divider().padding(.leading, 44) }
                    }
                }
                .padding(.vertical, 4)
                .glassEffect(in: .rect(cornerRadius: 20))
            }
            .padding(32)
            .padding(.bottom, 20)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ItemRow: View {
    @Binding var item: CleanupItem
    var fraction: Double
    var color: Color
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $item.isSelected) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .fixedSize()
                .tint(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            if let url = item.removal.url {
                Button {
                    revealInFinder(url)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
                .opacity(hovering ? 1 : 0)
            }
            SizeBar(fraction: fraction, color: color)
                .frame(width: 110)
            Text(item.size.bytes)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { item.isSelected.toggle() } }
        .onHover { hovering = $0 }
        .contextMenu {
            if let url = item.removal.url {
                Button("Show in Finder") { revealInFinder(url) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
        }
    }
}

// MARK: - Flush bar

struct FlushBar: View {
    @Environment(AppModel.self) private var model
    var action: () -> Void

    var body: some View {
        let size = model.selectedSize
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(size > 0 ? "\(size.bytes) of crap selected" : "Nothing selected. Your crap is safe. For now.")
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                HStack(spacing: 14) {
                    ForEach(Risk.allCases) { r in
                        HStack(spacing: 5) {
                            Circle().fill(r.color).frame(width: 7, height: 7)
                            Text("\(r.shortLabel) \(model.selected(for: r).bytes)")
                                .monospacedDigit()
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: action) {
                Label("Flush \(size > 0 ? size.bytes : "")", systemImage: "drop.fill")
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.glassProminent)
            .tint(model.selected(for: .high) > 0 ? .red : Brand.accent)
            .controlSize(.large)
            .disabled(size == 0)
        }
        .padding(.leading, 22)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .frame(maxWidth: 1036)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .animation(.snappy, value: size)
    }
}

import SwiftUI

// MARK: - Before the first scan (Overview pane)

struct WelcomePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Mascot(size: 140)
            VStack(spacing: 8) {
                Text("Your Mac is full of crap.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Let's find it, sort it, and flush it.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            DiskGauge(disk: model.disk)
            Button {
                Task { await model.scan() }
            } label: {
                Label("Sniff Out the Crap", systemImage: "magnifyingglass")
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            Text("Nothing gets deleted until you say so. We're messy, not reckless.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - While scanning (Overview pane; the sidebar fills in as categories turn up)

struct ScanPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: max(model.scanProgress, 0.02))
                    .stroke(Brand.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: model.scanProgress)
                VStack(spacing: 4) {
                    Text(model.foundSoFar.bytes)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(model.foundSoFar)))
                    Text("of crap so far")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)

            Quips(lines: Copy.scanning)

            Text("Checked \(model.finishedRules.count) of \(Rules.all.count) places")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Flushing and the report (a sheet over the results)

struct FlushSheet: View {
    @Environment(AppModel.self) private var model
    @State private var shown: Int64 = 0

    var body: some View {
        Group {
            if model.phase == .cleaning {
                cleaning
            } else if let report = model.report {
                done(report)
            }
        }
        .padding(28)
        .frame(width: 480)
        .interactiveDismissDisabled(model.phase == .cleaning)
    }

    private var cleaning: some View {
        VStack(spacing: 20) {
            Mascot(size: 110, mood: .flushing)
            Quips(lines: Copy.flushing, interval: 1.8)
            VStack(spacing: 8) {
                ProgressView(value: model.cleanProgress)
                Text(model.cleanStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func done(_ report: CleanReport) -> some View {
        VStack(spacing: 20) {
            Mascot(size: 110, mood: .proud)
            VStack(spacing: 6) {
                Text("Flushed \(shown.bytes)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(shown)))
                Text(Copy.doneLine(for: report.freed))
                    .foregroundStyle(.secondary)
            }

            Grid(horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    stat("Free before", report.freeBefore.bytes)
                    stat("Free now", report.freeAfter.bytes)
                    stat("Items flushed", "\(report.itemCount - report.failures.count)")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if report.touchedDocker {
                    callout("shippingbox.fill", .secondary,
                            "Restart Docker Desktop to actually get Docker's space back. It keeps everything in one big file and only lets go on a restart.")
                }
                if report.movedToTrash {
                    callout("trash.fill", .orange,
                            "Some of it is chilling in the Trash, so you can fish it back out. Empty the Trash when you're sure.")
                }
                if !report.failures.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.failures) { f in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name).font(.callout.weight(.medium))
                                    Text(f.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Label("\(report.failures.count) things didn't fully flush", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Sniff Again") {
                    model.showReport = false
                    Task { await model.scan() }
                }
                Button("Done") { model.showReport = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.smooth(duration: 1.2)) { shown = report.freed }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func callout(_ icon: String, _ color: Color, _ text: String) -> some View {
        Label {
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
    }
}

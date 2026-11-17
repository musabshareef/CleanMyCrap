import SwiftUI

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 26) {
                Mascot(size: 168)
                VStack(spacing: 10) {
                    Text("Clean My Crap")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                    Text("Your Mac is full of crap. Let's find it, sort it, and flush it.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                DiskGauge(disk: model.disk)
                    .padding(.top, 6)
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Sniff Out the Crap", systemImage: "magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
                Text("Nothing gets deleted until you say so. We're messy, not reckless.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

// MARK: - Scanning

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 30) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: max(model.scanProgress, 0.02))
                        .stroke(AngularGradient(colors: [Brand.peach, Brand.pink, Brand.peach], center: .center),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: model.scanProgress)
                    VStack(spacing: 4) {
                        Text(model.foundSoFar.bytes)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(model.foundSoFar)))
                        Text("of crap so far")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 230, height: 230)
                .padding(26)

                Quips(lines: Copy.scanning)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                        ForEach(Rules.all, id: \.id) { rule in
                            let done = model.finishedRules.contains(rule.id)
                            HStack(spacing: 8) {
                                Group {
                                    if done {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .transition(.scale.combined(with: .opacity))
                                    } else {
                                        ProgressView().controlSize(.small)
                                    }
                                }
                                .frame(width: 18)
                                Text(rule.name)
                                    .lineLimit(1)
                                    .foregroundStyle(done ? .secondary : .primary)
                                Spacer(minLength: 0)
                            }
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .card(in: Capsule())
                    }
                }
                .frame(maxWidth: 900)
            }
            .padding(40)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

// MARK: - Cleaning

struct CleaningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 26) {
                Mascot(size: 168, mood: .flushing)
                Quips(lines: Copy.flushing, interval: 1.8)
                VStack(spacing: 10) {
                    ProgressView(value: model.cleanProgress)
                        .progressViewStyle(.linear)
                    Text(model.cleanStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(width: 380)
                .padding(20)
                .card(cornerRadius: 18)
            }
            .padding(40)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

// MARK: - Done

struct DoneView: View {
    @Environment(AppModel.self) private var model
    @State private var shown: Int64 = 0

    var body: some View {
        let report = model.report
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 24) {
                    Mascot(size: 150, mood: .proud)
                    VStack(spacing: 8) {
                        Text("Flushed \(shown.bytes)")
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(shown)))
                        Text(Copy.doneLine(for: report?.freed ?? 0))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    if let report {
                        HStack(spacing: 12) {
                            stat("Free before", report.freeBefore.bytes, "internaldrive")
                            stat("Free now", report.freeAfter.bytes, "internaldrive.fill")
                            stat("Items flushed", "\(report.itemCount - report.failures.count)", "drop.fill")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            if report.touchedDocker {
                                callout("shippingbox.fill", .secondary,
                                        "Restart Docker Desktop to actually get Docker's space back. It keeps everything in one big file and only lets go on a restart.")
                            }
                            if report.movedToTrash {
                                callout("trash.fill", .orange,
                                        "High-risk stuff is chilling in the Trash, so you can fish it back out. Empty the Trash when you're sure to free that space.")
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
                                .padding(14)
                                .card()
                            }
                        }
                        .frame(maxWidth: 560)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await model.scan() }
                        } label: {
                            Label("Sniff Again", systemImage: "arrow.clockwise").padding(.horizontal, 8)
                        }
                        .buttonStyle(.glassProminent)
                        Button("Done") { model.startOver() }
                            .buttonStyle(.glass)
                    }
                    .controlSize(.extraLarge)
                }
                .padding(48)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.smooth(duration: 1.2)) { shown = model.report?.freed ?? 0 }
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(Brand.accent)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 160, height: 104)
        .card()
    }

    private func callout(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .card()
    }
}

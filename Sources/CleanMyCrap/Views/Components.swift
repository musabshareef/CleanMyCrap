import SwiftUI

/// Soft, slowly drifting mesh gradient behind the hero screens.
struct AmbientBackground: View {
    var tint: Color = .teal

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let x = Float(sin(t * 0.21)) * 0.18
            let y = Float(cos(t * 0.17)) * 0.18
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + x, 0.5 + y], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    tint.opacity(0.30), .mint.opacity(0.18), .indigo.opacity(0.22),
                    .cyan.opacity(0.14), .clear, tint.opacity(0.18),
                    .indigo.opacity(0.18), .mint.opacity(0.22), .cyan.opacity(0.26),
                ]
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        // Purely decorative: let clicks through to the title bar (double-click to zoom, dragging).
        .allowsHitTesting(false)
    }
}

/// The app's mascot: a very clean toilet in a glass bubble.
struct Mascot: View {
    var size: CGFloat = 150
    var symbol = "toilet.fill"
    var wiggle = false

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(LinearGradient(colors: [.teal, .cyan], startPoint: .top, endPoint: .bottom))
                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.2)), isActive: wiggle)
                .symbolEffect(.breathe, options: .repeat(.continuous), isActive: !wiggle)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.2, weight: .semibold))
                .foregroundStyle(.yellow.gradient)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeat(.continuous))
                .offset(x: size * 0.27, y: -size * 0.25)
        }
        .frame(width: size, height: size)
        .glassEffect(.regular.tint(.teal.opacity(0.12)), in: .circle)
    }
}

struct RiskBadge: View {
    let risk: Risk

    var body: some View {
        Label(risk.shortLabel, systemImage: risk.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(risk.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(risk.color.opacity(0.14), in: .capsule)
    }
}

/// Used vs free, as a glassy capsule.
struct DiskGauge: View {
    let disk: DiskInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Macintosh HD", systemImage: "internaldrive.fill")
                    .font(.headline)
                Spacer()
                Text("\(disk.free.bytes) free of \(disk.total.bytes)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(LinearGradient(colors: barColors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * disk.usedFraction, 12))
                }
            }
            .frame(height: 12)
        }
        .padding(18)
        .frame(width: 440)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    private var barColors: [Color] {
        disk.usedFraction > 0.9 ? [.orange, .red] : disk.usedFraction > 0.75 ? [.teal, .orange] : [.teal, .cyan]
    }
}

/// Cycles through funny lines.
struct Quips: View {
    let lines: [String]
    var interval: TimeInterval = 2.4

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { ctx in
            let i = Int(ctx.date.timeIntervalSinceReferenceDate / interval) % lines.count
            Text(lines[i])
                .id(i)
                .transition(.push(from: .bottom).combined(with: .opacity))
                .animation(.smooth, value: i)
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(height: 28)
        .clipped()
    }
}

func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

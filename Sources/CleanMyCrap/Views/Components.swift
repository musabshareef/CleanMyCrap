import SwiftUI

/// Colors lifted from the app icon's sunset.
enum Brand {
    static let peach = Color(red: 1.00, green: 0.70, blue: 0.42)
    static let pink = Color(red: 0.94, green: 0.31, blue: 0.48)
    /// Buttons, selection, progress.
    static let accent = Color(red: 0.93, green: 0.38, blue: 0.43)
    static let gradient = LinearGradient(colors: [peach, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A clean, neutral backdrop with the faintest warm glow up top.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Brand.peach.opacity(0.10), .clear],
                           center: .top, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
        // Purely decorative: let clicks through to the title bar (double-click to zoom, dragging).
        .allowsHitTesting(false)
    }
}

/// A flat content surface. Liquid Glass is reserved for controls and navigation
/// (per the HIG), so content groups use a quiet fill and a hairline edge instead.
struct CardBackground<S: InsettableShape>: View {
    var shape: S

    var body: some View {
        shape.fill(.quinary)
            .overlay(shape.strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }
}

extension View {
    func card(cornerRadius: CGFloat = 16) -> some View {
        background(CardBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    func card<S: InsettableShape>(in shape: S) -> some View {
        background(CardBackground(shape: shape))
    }
}

/// The app icon itself, doing a little performance.
struct Mascot: View {
    enum Mood { case idle, flushing, proud }

    var size: CGFloat = 168
    var mood: Mood = .idle

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if mood == .proud {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: size * 0.26, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .background(Circle().fill(.white).padding(4))
                        .offset(x: -size * 0.04, y: -size * 0.04)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .phaseAnimator(phases) { view, phase in
                view
                    .rotationEffect(.degrees(mood == .flushing ? phase * 7 : 0), anchor: .bottom)
                    .offset(y: mood == .idle ? phase * -6 : 0)
            } animation: { _ in
                mood == .flushing ? .easeInOut(duration: 0.18) : .easeInOut(duration: 1.6)
            }
    }

    private var phases: [Double] {
        switch mood {
        case .idle: [0, 1]
        case .flushing: [0, -1, 1, -1, 1, 0, 0, 0]
        case .proud: [0]
        }
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

/// Used vs free.
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
        .card(cornerRadius: 18)
    }

    private var barColors: [Color] {
        disk.usedFraction > 0.9 ? [.orange, .red] : [Brand.peach, Brand.pink]
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

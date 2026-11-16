// Renders the app icon to a 1024×1024 PNG. Usage: swift scripts/make-icon.swift out.png
import SwiftUI
import AppKit

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.78, blue: 0.74),
                                              Color(red: 0.20, green: 0.42, blue: 0.86)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.35), .clear],
                                             startPoint: .top, endPoint: .center))
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
            Image(systemName: "toilet.fill")
                .font(.system(size: 400, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                .offset(x: -20, y: 30)
            Image(systemName: "sparkles")
                .font(.system(size: 210, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.86, blue: 0.3))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .offset(x: 230, y: -220)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render() throws {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
        fatalError("render failed")
    }
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
try MainActor.assumeIsolated { try render() }

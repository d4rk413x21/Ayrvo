import AppKit
import SwiftUI

struct RecordDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ayrvoActionColor) private var actionColor
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(actionColor)
            .frame(width: 10, height: 10)
            .opacity(!reduceMotion && pulsing ? 0.35 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = !reduceMotion }
            .onChange(of: reduceMotion) { pulsing = !reduceMotion }
            .accessibilityHidden(true)
    }
}

struct LevelMeter: View {
    var levels: [Float]

    var body: some View {
        MeterBars(levels: levels)
    }
}

/// Bottom-anchored capsules driven by per-segment RMS from the mic tap.
struct MeterBars: View {
    var levels: [Float]
    /// When set, downsamples the full level array (e.g. 12 → 3 for the pill).
    var barCount: Int?

    private let minimumHeight: CGFloat = 4
    private let maximumHeight: CGFloat = 14
    private let containerHeight: CGFloat = 16

    var body: some View {
        let displayLevels = displayedLevels()
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(displayLevels.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.mint)
                    .frame(
                        width: 4,
                        height: barHeight(for: displayLevels[index])
                    )
            }
        }
        .frame(height: containerHeight, alignment: .bottom)
        .animation(.easeOut(duration: 0.08), value: displayLevels)
    }

    private func displayedLevels() -> [Float] {
        guard let barCount, barCount < levels.count else { return levels }
        return (0..<barCount).map { index in
            let start = index * levels.count / barCount
            let end = (index + 1) * levels.count / barCount
            return levels[start..<end].max() ?? 0
        }
    }

    private func barHeight(for level: Float) -> CGFloat {
        let clamped = CGFloat(min(max(level, 0), 1))
        return minimumHeight + ((maximumHeight - minimumHeight) * clamped)
    }
}

import SwiftUI
import AppKit

struct TaskInsightsChart: View {
    @Environment(\.colorScheme) private var scheme

    let insights: [TaskDayInsight]
    let accent: Color

    private var maxTotal: Int {
        max(1, insights.map(\.total).max() ?? 0)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(insights, id: \.date) { insight in
                VStack(spacing: 4) {
                    VStack(spacing: 1) {
                        Rectangle()
                            .fill(accent.opacity(0.8))
                            .frame(height: barHeight(insight.completed))
                        Rectangle()
                            .fill(accent.opacity(0.2))
                            .frame(height: barHeight(insight.pending))
                    }
                    Text(dayLabel(insight.date))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiary(scheme))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func barHeight(_ count: Int) -> CGFloat {
        guard maxTotal > 0 else { return 0 }
        return CGFloat(count) / CGFloat(maxTotal) * 48
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(2))
    }
}

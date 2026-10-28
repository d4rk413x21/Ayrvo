import AppKit
import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                usedWidth = max(usedWidth, x - spacing)
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + (index < subviews.count - 1 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }

        usedWidth = max(usedWidth, x)
        let width = maxWidth.isFinite ? min(maxWidth, usedWidth) : usedWidth
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension View {
    func badgeStyle(_ color: Color) -> some View {
        font(.ayrvo(11, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
    }

    func cardStyle() -> some View {
        modifier(CardBackground())
    }

    /// Full-height calendar color bar on the leading edge of event rows.
    func calendarEventIndicator(_ color: Color, width: CGFloat = 3, spacing: CGFloat = 8) -> some View {
        padding(.leading, width + spacing)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .frame(width: width)
            }
    }
    /// Applies `transform` to `self` only when `value` is non-nil, so optional
    /// accessibility actions / modifiers can be attached conditionally without
    /// `if`-branching the view tree (which would break ViewBuilder identity).
    @ViewBuilder
    func ifLet<T, R: View>(_ value: T?, transform: (Self, T) -> R) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

import AppKit
import SwiftUI

struct StateBadge: View {
    @Environment(\.ayrvoActionColor) private var actionColor
    let meeting: Meeting
    let stage: String?

    var body: some View {
        switch meeting.state {
        case .prep:
            EmptyView()
        case .recording:
            Label("Recording", systemImage: "record.circle")
                .badgeStyle(actionColor)
        case .processing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(stage ?? "Processing…")
            }
            .badgeStyle(Theme.honey)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle")
                .badgeStyle(.orange)
        case .ready:
            EmptyView()
        }
    }
}

/// Flags which engine wrote the summary: Apple Intelligence, Claude, or Codex.
struct ProviderBadge: View {
    let provider: String?

    var body: some View {
        if provider == "claude" {
            badgeLabel("Claude", icon: "sparkles", color: Theme.blueberry)
        } else if provider == "codex" {
            badgeLabel("Codex", icon: "sparkles", color: Theme.raspberry)
        } else if provider == "apple" {
            badgeLabel("Apple Intelligence", icon: "apple.intelligence", color: Theme.mint)
        }
    }

    private func badgeLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
        }
        .badgeStyle(color)
    }
}

struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ayrvo(11, .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: 160, alignment: .leading)
            .background(Theme.honey.opacity(0.16), in: Capsule())
            .foregroundStyle(.primary)
    }
}

/// Attendee chips with a compact default — show `limit` items, then "See more".
struct ExpandableChipFlow: View {
    @Environment(\.colorScheme) private var scheme
    let items: [String]
    var limit: Int = 3
    @State private var expanded = false

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(visibleItems, id: \.self) { Chip(text: $0) }
            if items.count > limit {
                Button(expanded ? "See less" : "See more") {
                    expanded.toggle()
                }
                .font(.ayrvo(11, .medium))
                .foregroundStyle(Theme.blueberry(scheme))
                .buttonStyle(.plain)
            }
        }
    }

    private var visibleItems: [String] {
        expanded ? items : Array(items.prefix(limit))
    }
}

/// Wraps attendee-style chips onto new rows instead of overflowing the container width.

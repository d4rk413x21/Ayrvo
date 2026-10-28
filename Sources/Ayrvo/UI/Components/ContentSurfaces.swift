import AppKit
import SwiftUI

struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

struct MeetingNoticeBanner: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor

    let presentation: MeetingNotice.Presentation
    var primaryActionTitle: String?
    var primaryActionIcon: String?
    var primaryAction: (() -> Void)?

    private var accent: Color {
        presentation.isEmptyTranscript ? Theme.honey(scheme) : Theme.blueberry(scheme)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(scheme == .dark ? 0.16 : 0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: presentation.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.ayrvo(13, .semibold))
                    .foregroundStyle(Theme.heading(scheme))
                Text(presentation.message)
                    .font(.ayrvo(12))
                    .foregroundStyle(Theme.secondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let primaryActionTitle, let primaryAction {
                Button(action: primaryAction) {
                    if let primaryActionIcon {
                        Label(primaryActionTitle, systemImage: primaryActionIcon)
                            .font(.ayrvo(12, .semibold))
                    } else {
                        Text(primaryActionTitle)
                            .font(.ayrvo(12, .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryActionIcon == "mic.fill" ? Theme.mint(scheme) : actionColor)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        }
    }
}

struct AyrvoMark: View {
    var size: CGFloat = 56

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct EmptyStateView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor
    let title: String
    let message: String
    var actionTitle: String?
    var actionIcon: String?
    var action: (() -> Void)?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?
    var tips: [String] = []

    var body: some View {
        VStack(spacing: 14) {
            AyrvoMark()
                .accessibilityHidden(true)
            Text(title).font(.ayrvo(17, .semibold))
                .foregroundStyle(Theme.heading(scheme))
            Text(message)
                .font(.ayrvo(13))
                .foregroundStyle(Theme.secondary(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)

            if !tips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tips, id: \.self) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("·")
                                .font(.ayrvo(12, .bold))
                            Text(tip)
                                .font(.ayrvo(12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Theme.tertiary(scheme))
                    }
                }
                .frame(maxWidth: 340, alignment: .leading)
                .padding(.top, 2)
            }

            actionRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var actionRow: some View {
        let hasPrimary = actionTitle != nil && action != nil
        let hasSecondary = secondaryActionTitle != nil && secondaryAction != nil
        if hasPrimary || hasSecondary {
            HStack(spacing: 10) {
                if let actionTitle, let action {
                    Button(action: action) {
                        if let actionIcon {
                            Label(actionTitle, systemImage: actionIcon)
                        } else {
                            Text(actionTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(actionColor)
                    .controlSize(.regular)
                }
                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
            .padding(.top, tips.isEmpty ? 0 : 4)
        }
    }
}

/// Minimal markdown display for summaries: headings, bullets, checkboxes,
/// horizontal rules (`---`), inline bold/italic. Anything else renders as a plain paragraph.

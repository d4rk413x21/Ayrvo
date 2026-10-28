import AppKit
import SwiftUI

extension View {
    /// SwiftUI `Menu` on macOS ignores `role: .destructive`; tint the backing `NSMenuItem` red.
    func destructiveMenuItemStyle() -> some View {
        background(DestructiveMenuItemStyle())
    }
}

private struct DestructiveMenuItemStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> DestructiveMenuItemStyleView {
        DestructiveMenuItemStyleView()
    }

    func updateNSView(_ nsView: DestructiveMenuItemStyleView, context: Context) {
        nsView.applyStyle()
    }
}

private final class DestructiveMenuItemStyleView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()
    }

    func applyStyle() {
        guard let item = enclosingMenuItem else { return }
        let title = item.title
        guard !title.isEmpty else { return }
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.systemRed]
        )
    }
}

struct ConferenceVideoIcon: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "video.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.blueberry(scheme))
    }
}

struct ConferenceJoinButton: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var app: AppState
    let label: String
    let url: URL
    var prominent: Bool = false
    /// When non-nil, the button becomes a split button: primary "Join & Record"
    /// starts a recording for this calendar event AND opens the conference URL;
    /// the menu also offers "Join only" (plain open) and "Record only"
    /// (starts recording without joining). nil = the legacy single-action button.
    var calendarEvent: CalendarEventSummary? = nil

    var body: some View {
        Group {
            if let event = calendarEvent {
                splitButton(for: event)
            } else {
                singleButton
            }
        }
    }

    private var singleButton: some View {
        Group {
            if prominent {
                Button {
                    ConferenceJoiner.open(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(label)
                            .font(.ayrvo(14, .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Theme.blueberry(scheme), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    ConferenceJoiner.open(url)
                } label: {
                    Label(label, systemImage: "video.fill")
                        .font(.ayrvo(11, .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.blueberry(scheme))
                .controlSize(.regular)
            }
        }
    }

    /// Split button: primary "Join & Record" opens the conference and starts a
    /// calendar-linked recording in one tap. The chevron opens a menu with the
    /// plain "Join only" and "Record only" alternatives so the user keeps the
    /// single-tap convenience without losing the original behavior.
    private func splitButton(for event: CalendarEventSummary) -> some View {
        HStack(spacing: 0) {
            Button {
                joinAndRecord(event)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .font(.system(size: prominent ? 14 : 11, weight: .semibold))
                    if prominent {
                        Text("Join & Record")
                            .font(.ayrvo(14, .semibold))
                    }
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, prominent ? 16 : 10)
                .padding(.vertical, prominent ? 10 : 6)
            }
            .buttonStyle(.plain)
            .background(Theme.blueberry(scheme), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Join meeting and start recording")
            .disabled(app.isRecording)
            .help(app.isRecording
                  ? "A recording is already in progress"
                  : "Open the meeting and start recording")

            Menu {
                Button("Join only") { ConferenceJoiner.open(url) }
                Button {
                    Task { await app.startRecording(calendarEvent: event) }
                } label: {
                    Label("Record only", systemImage: "record.circle")
                }
                .disabled(app.isRecording)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: prominent ? 14 : 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: prominent ? 32 : 24,
                           height: prominent ? 32 : 24)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Meeting join and recording options")
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func joinAndRecord(_ event: CalendarEventSummary) {
        ConferenceJoiner.open(url)
        Task { await app.startRecording(calendarEvent: event) }
    }
}

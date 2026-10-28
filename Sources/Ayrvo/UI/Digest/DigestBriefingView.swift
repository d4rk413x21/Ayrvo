import SwiftUI
import AppKit

struct DigestBriefingView: View {
    @Environment(\.colorScheme) private var scheme
    let digest: DailyDigest
    let digestMode: DailyDigestView.DigestMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if digest.yesterdayMeetings.isEmpty {
                noMeetingsCard
            } else {
                meetingsCard(digest)
            }


            if !digest.todayAgenda.isEmpty {
                agendaCard(digest)
            }

            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        DailyDigestGenerator().formatDigest(digest),
                        forType: .string)
                } label: {
                    Label("Copy Digest", systemImage: "doc.on.doc")
                        .font(.ayrvo(12, .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var noMeetingsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.tertiary(scheme))
            Text("No meetings \(digestMode == .today ? "today" : "yesterday")")
                .font(.ayrvo(13, .semibold))
                .foregroundStyle(Theme.secondary(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func meetingsCard(_ digest: DailyDigest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.ayrvo(13, .medium))
                    .foregroundStyle(Theme.blueberry(scheme))
                Text("\(digest.yesterdayMeetings.count) meetings \(digestMode == .today ? "today" : "yesterday")")
                    .font(.ayrvo(14, .semibold))
                    .foregroundStyle(Theme.heading(scheme))
                Spacer()
            }
            ForEach(digest.yesterdayMeetings, id: \.id) { meeting in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Theme.mint(scheme))
                    Text(meeting.title)
                        .font(.ayrvo(12, .medium))
                        .foregroundStyle(Theme.heading(scheme))
                        .lineLimit(1)
                    Spacer()
                    Text(RelativeTimeFormatter.naturalRelative(to: meeting.createdAt))
                        .font(.ayrvo(10))
                        .foregroundStyle(Theme.tertiary(scheme))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func agendaCard(_ digest: DailyDigest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "calendar")
                    .font(.ayrvo(13, .medium))
                    .foregroundStyle(Theme.mint(scheme))
                Text(digestMode == .today ? "Upcoming" : "Today's Agenda")
                    .font(.ayrvo(14, .semibold))
                    .foregroundStyle(Theme.heading(scheme))
                Spacer()
            }
            ForEach(digest.todayAgenda.filter { $0.start >= Date() }, id: \.rowID) { event in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(event.calendarColor.swiftUIColor)
                    Text(event.title)
                        .font(.ayrvo(12, .medium))
                        .foregroundStyle(Theme.heading(scheme))
                        .lineLimit(1)
                    Spacer()
                    Text(CalendarTimeFormatter.timeRange(start: event.start, end: event.end))
                        .font(.ayrvo(10))
                        .foregroundStyle(Theme.tertiary(scheme))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

}

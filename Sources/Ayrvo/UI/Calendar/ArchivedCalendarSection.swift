import SwiftUI

struct ArchivedCalendarSection: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var archivedStore: ArchivedEventStore
    @ObservedObject var calendar: CalendarStore

    @State private var showArchived = false

    var body: some View {
        Group {
            if archivedStore.hasAny {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showArchived.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "archivebox.fill")
                                .font(.ayrvo(13, .medium))
                                .foregroundStyle(Theme.secondary(scheme))
                            Text("Archived")
                                .font(.ayrvo(13, .semibold))
                                .foregroundStyle(Theme.secondary(scheme))
                            Spacer()
                            Text("\(archivedStore.archivedTitles.count + archivedStore.archivedEvents.count)")
                                .font(.ayrvo(11))
                                .foregroundStyle(Theme.tertiary(scheme))
                            Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                .font(.ayrvo(10))
                                .foregroundStyle(Theme.tertiary(scheme))
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showArchived {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(archivedStore.archivedTitles).sorted(), id: \.self) { title in
                                archivedRow(title: title, isSeries: true)
                            }
                            ForEach(archivedStore.archivedEvents) { evt in
                                archivedRow(title: evt.title, isSeries: false, eventID: evt.id)
                            }
                            Divider()
                                .padding(.top, 4)
                            Button {
                                archivedStore.clearAll()
                                Task { await calendar.refreshAgenda() }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.up.out.of.square")
                                    Text("Unarchive all")
                                }
                                .font(.ayrvo(11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.blueberry)
                            .padding(.top, 4)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func archivedRow(title: String, isSeries: Bool, eventID: String? = nil) -> some View {
        HStack {
            Image(systemName: isSeries ? "archivebox.fill" : "archivebox")
                .font(.ayrvo(11))
                .foregroundStyle(Theme.tertiary(scheme))
            Text(title)
                .font(.ayrvo(12))
                .foregroundStyle(Theme.secondary(scheme))
                .lineLimit(1)
            Spacer()
            Button {
                if isSeries {
                    archivedStore.unarchiveTitle(title)
                } else if let eventID {
                    archivedStore.unarchiveEvent(id: eventID)
                }
                Task { await calendar.refreshAgenda() }
            } label: {
                Image(systemName: "arrow.up.out.of.square")
                    .font(.ayrvo(11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.blueberry)
            .help("Unarchive")
            .accessibilityLabel("Unarchive")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                if isSeries {
                    archivedStore.unarchiveTitle(title)
                } else if let eventID {
                    archivedStore.unarchiveEvent(id: eventID)
                }
                Task { await calendar.refreshAgenda() }
            } label: {
                Label("Unarchive", systemImage: "arrow.up.out.of.square")
            }
        }
    }

}

import SwiftUI

struct MeetingDecisionsSection: View {
    @Environment(\.colorScheme) private var scheme
    @State private var decisionsExpanded = true

    let segments: [TranscriptSegment]
    let speakers: [Speaker]
    let isRecording: Bool

    var body: some View {
        let decisions = DecisionExtractor.extract(from: segments, speakers: speakers)
        if !decisions.isEmpty, !isRecording {
            DisclosureGroup(isExpanded: $decisionsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(decisions) { decision in
                        MeetingDecisionCard(decision: decision)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mint(scheme))
                    Text("Decisions")
                        .font(.ayrvo(12, .semibold))
                        .foregroundStyle(Theme.secondary(scheme))
                    Text("\(decisions.count)")
                        .font(.ayrvo(11, .semibold))
                        .foregroundStyle(Theme.tertiary(scheme))
                }
            }
        }
    }
}

private struct MeetingDecisionCard: View {
    @Environment(\.colorScheme) private var scheme
    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(decision.speakerName)
                    .font(.ayrvo(11, .semibold))
                    .foregroundStyle(Theme.secondary(scheme))
                Spacer(minLength: 0)
                Text(MeetingArchive.timestamp(decision.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.tertiary(scheme))
            }
            Text(decision.quote)
                .font(.ayrvo(13))
                .foregroundStyle(Theme.heading(scheme))
                .textSelection(.enabled)
                .lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(decision.speakerName) at \(MeetingArchive.timestamp(decision.timestamp)): \(decision.quote)")
    }
}

import AppKit
import SwiftUI

struct MeetingAskPanel: View {
  @Environment(\.colorScheme) private var scheme
  @Environment(\.ayrvoActionColor) private var actionColor
  let meeting: Meeting
  let canAskAboutMeeting: Bool
  let preferredAIProvider: AIProvider
  @Binding var askInput: String
  let onAsk: (String) -> Void
  let onCollapse: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      panelHeader(
        leading: {
          if !askInput.isEmpty {
            Button {
              askInput = ""
            } label: {
              Label("Clear", systemImage: "xmark.circle")
                .font(.ayrvo(11, .medium))
                .foregroundStyle(Theme.tertiary(scheme))
            }
            .buttonStyle(.plain)
            .help("Clear the question")
            .accessibilityLabel("Clear the question")
          }
        }, title: nil)

      if canAskAboutMeeting {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(MeetingAISuggestions.forMeeting(meeting), id: \.self) { suggestion in
            Button {
              launchAsk(suggestion)
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "square")
                  .font(.system(size: 11))
                  .foregroundStyle(Theme.tertiary(scheme))
                Text(suggestion)
                  .font(.ayrvo(13))
                  .foregroundStyle(Theme.heading(scheme))
                Spacer()
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 8)
      } else {
        Text(
          "Record the meeting or add notes first — then you can ask questions about what happened."
        )
        .font(.ayrvo(12))
        .foregroundStyle(Theme.secondary(scheme))
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
      }

      askInputBar
    }
  }

  private var askInputBar: some View {
    HStack(spacing: 10) {
      TextField("Ask anything", text: $askInput)
        .textFieldStyle(.plain)
        .font(.ayrvo(13))
        .disabled(!canAskAboutMeeting)
        .onSubmit { launchTypedAsk() }

      Text(preferredAIProvider.displayName)
        .font(.ayrvo(10, .medium))
        .foregroundStyle(Theme.tertiary(scheme))

      Button(action: launchTypedAsk) {
        Image(systemName: "arrow.up")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 26, height: 26)
          .background(
            Circle().fill(
              canAskAboutMeeting
                && !askInput.trimmingCharacters(in: .whitespaces).isEmpty
                ? actionColor
                : Color.secondary.opacity(0.25))
          )
      }
      .buttonStyle(.plain)
      .disabled(!canAskAboutMeeting || askInput.trimmingCharacters(in: .whitespaces).isEmpty)
      .accessibilityLabel("Send question")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Theme.chip(scheme), in: Capsule())
    .overlay {
      Capsule().strokeBorder(Theme.mint(scheme).opacity(0.35), lineWidth: 1)
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 12)
  }

  private func panelHeader<Leading: View>(
    @ViewBuilder leading: () -> Leading = { EmptyView() },
    title: String?
  ) -> some View {
    HStack(spacing: 8) {
      leading()
      if let title {
        Text(title)
          .font(.ayrvo(12, .semibold))
          .foregroundStyle(Theme.secondary(scheme))
      }
      Spacer()
      MeetingPanelCollapseButton(onCollapse: onCollapse)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .overlay(alignment: .bottom) { Divider().opacity(0.3) }
  }

  private func launchTypedAsk() {
    let text = askInput.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    launchAsk(text)
  }

  private func launchAsk(_ question: String) {
    onAsk(question)
    askInput = ""
  }
}

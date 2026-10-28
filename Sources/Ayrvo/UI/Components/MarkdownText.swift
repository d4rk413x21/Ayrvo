import AppKit
import SwiftUI

struct MarkdownText: View {
    enum Style {
        case card
        case document
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor
    let markdown: String
    var style: Style = .card

    private var bodySize: CGFloat { style == .document ? 13 : 14 }
    private var lineSpacing: CGFloat { style == .document ? 5 : 7 }
    private var bulletColor: Color {
        style == .document ? Theme.tertiary(scheme) : Theme.honey(scheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated()),
                    id: \.offset) { _, rawLine in
                line(String(rawLine))
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func line(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Spacer().frame(height: style == .document ? 4 : 2)
        } else if trimmed.hasPrefix("# ") {
            inline(String(trimmed.dropFirst(2)))
                .font(style == .document ? .ayrvo(15, .semibold) : .ayrvo(22, .bold))
                .foregroundStyle(Theme.heading(scheme))
                .padding(.top, style == .document ? 10 : 4)
        } else if trimmed.hasPrefix("## ") {
            inline(String(trimmed.dropFirst(3)))
                .font(style == .document ? .ayrvo(14, .semibold) : .ayrvo(16, .bold))
                .foregroundStyle(
                    style == .document
                        ? Theme.heading(scheme)
                        : Theme.sectionTitle(scheme, accent: actionColor))
                .padding(.top, style == .document ? 8 : 8)
        } else if trimmed.hasPrefix("### ") {
            inline(String(trimmed.dropFirst(4)))
                .font(.ayrvo(bodySize, .semibold))
                .foregroundStyle(Theme.heading(scheme))
                .padding(.top, 4)
        } else if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: trimmed.hasPrefix("- [x] ") ? "checkmark.square.fill" : "square")
                    .foregroundStyle(bulletColor)
                    .font(.system(size: 12))
                inline(String(trimmed.dropFirst(6)))
                    .font(.ayrvo(bodySize))
                    .foregroundStyle(Theme.secondary(scheme))
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(bulletColor).frame(width: 4, height: 4)
                    .padding(.top, 6)
                inline(String(trimmed.dropFirst(2)))
                    .font(.ayrvo(bodySize))
                    .foregroundStyle(Theme.secondary(scheme))
            }
            .padding(.leading, style == .document ? 4 : 0)
        } else if Self.isHorizontalRule(trimmed) {
            Divider()
                .opacity(style == .document ? 0.35 : 0.5)
                .padding(.vertical, style == .document ? 6 : 4)
        } else {
            inline(trimmed)
                .font(.ayrvo(bodySize))
                .foregroundStyle(Theme.secondary(scheme))
        }
    }

    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }

    /// Markdown horizontal rule: `---`, `***`, or `___` (3+ chars, spaces allowed).
    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let char = compact.first else { return false }
        guard char == "-" || char == "*" || char == "_" else { return false }
        return compact.allSatisfy { $0 == char }
    }
}

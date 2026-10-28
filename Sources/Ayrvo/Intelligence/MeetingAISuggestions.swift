import Foundation

enum MeetingAISuggestions {
    static func forMeeting(_ meeting: Meeting) -> [String] {
        var items = ["Summarize this meeting", "List action items", "Write follow-up email"]
        if let speaker = meeting.speakers.first(where: { !$0.isMe }) {
            items.append("What did \(speaker.name) say?")
        }
        return items
    }

    static let library = [
        "Summarize my meetings this week",
        "What action items do I have?",
        "What decisions came out of recent calls?",
        "List open questions from recent meetings",
        "Who have I met with most this month?",
    ]
}

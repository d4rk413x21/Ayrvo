import Foundation

final class MeetingsCLI {
    enum Command: Equatable {
        case help
        case list(limit: Int, offset: Int)
        case search(query: String, limit: Int, offset: Int)
        case show(id: String)
        case transcript(id: String)
        case live(minutes: Int?)
    }

    enum UsageError: LocalizedError, Equatable {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let value): return value
            }
        }
    }

    static let usage = """
    Usage:
      Ayrvo meetings list [--limit N] [--offset N]
      Ayrvo meetings search <query> [--limit N] [--offset N]
      Ayrvo meetings show <meeting-uuid>
      Ayrvo meetings transcript <meeting-uuid>
      Ayrvo meetings live [--minutes N]
      Ayrvo meetings help
    """

    private let service: MeetingCommandService

    init(service: MeetingCommandService) {
        self.service = service
    }

    static func parse(arguments originalArguments: [String]) throws -> Command {
        var arguments = originalArguments
        if arguments.first == "meetings" { arguments.removeFirst() }
        guard let name = arguments.first else { return .help }
        let rest = Array(arguments.dropFirst())

        switch name {
        case "help", "--help", "-h":
            guard rest.isEmpty else {
                throw UsageError.message("Unexpected argument '\(rest[0])' after help")
            }
            return .help
        case "list":
            let options = try parsePageOptions(rest, allowPositionals: false)
            return .list(limit: options.limit, offset: options.offset)
        case "search":
            let options = try parsePageOptions(rest, allowPositionals: true)
            let query = options.positionals.joined(separator: " ")
            guard !query.isEmpty else {
                throw UsageError.message("Search query is required")
            }
            return .search(query: query, limit: options.limit, offset: options.offset)
        case "show":
            return .show(id: try parseMeetingID(rest))
        case "transcript":
            return .transcript(id: try parseMeetingID(rest))
        case "live":
            return .live(minutes: try parseLiveOptions(rest))
        default:
            throw UsageError.message("Unknown meetings command '\(name)'")
        }
    }

    @discardableResult
    func run(
        arguments: [String],
        output: (String) -> Void,
        error errorOutput: (String) -> Void
    ) -> Int32 {
        do {
            let command = try Self.parse(arguments: arguments)
            let text: String
            switch command {
            case .help:
                text = Self.usage
            case .list(let limit, let offset):
                text = service.list(limit: limit, offset: offset)
            case .search(let query, let limit, let offset):
                text = try service.search(query: query, limit: limit, offset: offset)
            case .show(let id):
                text = try service.show(id: id)
            case .transcript(let id):
                text = try service.transcript(id: id)
            case .live(let minutes):
                text = service.live(minutes: minutes)
            }
            output(text)
            return 0
        } catch let parseError as UsageError {
            errorOutput("Error: \(parseError.localizedDescription)\n\n\(Self.usage)")
            return 2
        } catch {
            errorOutput("Error: \(error.localizedDescription)")
            return 1
        }
    }

    private struct PageOptions {
        var limit = 20
        var offset = 0
        var positionals: [String] = []
    }

    private static func parsePageOptions(
        _ arguments: [String],
        allowPositionals: Bool
    ) throws -> PageOptions {
        var result = PageOptions()
        var seen: Set<String> = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--limit", "--offset":
                guard seen.insert(argument).inserted else {
                    throw UsageError.message("Duplicate option '\(argument)'")
                }
                let value = try integerValue(for: argument, arguments: arguments, valueIndex: index + 1)
                if argument == "--limit" {
                    result.limit = max(1, min(200, value))
                } else {
                    guard value >= 0 else {
                        throw UsageError.message("--offset must be non-negative")
                    }
                    result.offset = value
                }
                index += 2
            default:
                if argument.hasPrefix("--") {
                    throw UsageError.message("Unknown option '\(argument)'")
                }
                guard allowPositionals else {
                    throw UsageError.message("Unexpected argument '\(argument)'")
                }
                result.positionals.append(argument)
                index += 1
            }
        }
        return result
    }

    private static func parseMeetingID(_ arguments: [String]) throws -> String {
        guard let id = arguments.first else {
            throw UsageError.message("Meeting UUID is required")
        }
        guard arguments.count == 1 else {
            throw UsageError.message("Unexpected argument '\(arguments[1])'")
        }
        guard UUID(uuidString: id) != nil else {
            throw UsageError.message("'\(id)' must be a meeting UUID")
        }
        return id
    }

    private static func parseLiveOptions(_ arguments: [String]) throws -> Int? {
        guard !arguments.isEmpty else { return nil }
        var minutes: Int?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument == "--minutes" else {
                if argument.hasPrefix("--") {
                    throw UsageError.message("Unknown option '\(argument)'")
                }
                throw UsageError.message("Unexpected argument '\(argument)'")
            }
            guard minutes == nil else {
                throw UsageError.message("Duplicate option '--minutes'")
            }
            let value = try integerValue(for: argument, arguments: arguments, valueIndex: index + 1)
            guard value >= 0 else {
                throw UsageError.message("--minutes must be non-negative")
            }
            minutes = value
            index += 2
        }
        return minutes
    }

    private static func integerValue(
        for option: String,
        arguments: [String],
        valueIndex: Int
    ) throws -> Int {
        guard valueIndex < arguments.count else {
            throw UsageError.message("\(option) requires a value")
        }
        let rawValue = arguments[valueIndex]
        guard let value = Int(rawValue) else {
            throw UsageError.message("\(option) must be an integer")
        }
        return value
    }
}

import Foundation

struct ModuleInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String?
    let available: Bool
    let canImport: Bool
    let actions: [ModuleAction]?

    var symbol: String { icon?.isEmpty == false ? icon! : "square.grid.2x2" }
}

/// One-tap prompt from the module's jendapp.toml; starts a new chat.
struct ModuleAction: Codable, Hashable, Identifiable {
    let title: String
    let icon: String?
    let prompt: String
    let input: String? // "month" → pick a month first; fills {month}
    let confirm: ActionConfirm?

    var id: String { title }

    func resolved(month: String?) -> (prompt: String, confirm: ActionConfirm?) {
        func fill(_ s: String) -> String { month.map { s.replacingOccurrences(of: "{month}", with: $0) } ?? s }
        return (fill(prompt), confirm.map { ActionConfirm(title: $0.title, prompt: fill($0.prompt)) })
    }
}

/// Follow-up button offered after an action's run finishes (e.g. "Send to Clockify").
struct ActionConfirm: Codable, Hashable {
    let title: String
    let prompt: String
}

struct SessionInfo: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let updatedAt: Date
}

struct SessionMessage: Codable, Hashable {
    let role: String
    let text: String
    let timestamp: Date?
}

struct InboxItem: Codable, Identifiable, Hashable {
    let id: String
    let filename: String
    let size: Int64
    let status: String // pending | routed | skipped | failed
    let moduleId: String?
    let destPath: String?
    let error: String?
    let createdAt: Date
}

struct Job: Codable, Identifiable, Hashable {
    let id: String
    let moduleId: String
    let kind: String // chat | import
    let sessionId: String
    let status: String // queued | running | done | failed
    let prompt: String
    let result: String?
    let error: String?
    let costUsd: Double?
    let denials: String?
    let createdAt: Date
    let finishedAt: Date?

    var isFinished: Bool { status == "done" || status == "failed" }
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = APIDate.parse(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()
}

/// Go emits RFC 3339 with up to 9 fractional digits; Foundation parses at most 3.
nonisolated enum APIDate {
    static func parse(_ s: String) -> Date? {
        var s = s
        if let dot = s.firstIndex(of: "."),
           let end = s[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let frac = s[s.index(after: dot)..<end]
            s.replaceSubrange(dot..<end, with: "." + String(frac.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0))
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

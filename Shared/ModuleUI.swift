import Foundation

// Screens a module declares in its jendapp.toml ([[views]], [[operations]]).
// The app draws them with a fixed set of building blocks; the data comes from
// the module's own commands via GET /api/modules/{id}/views/{view}.

struct ViewSpec: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let icon: String?
    let type: String // table
    let groupBy: String?
    let columns: [ColumnSpec]
    let stats: [StatSpec]?
    let filter: FilterSpec?
    let rowActions: [String]?
    let actions: [String]?
    let params: [String]

    func columns(_ role: String) -> [ColumnSpec] { columns.filter { $0.role == role } }
    func column(_ key: String) -> ColumnSpec? { columns.first { $0.key == key } }
}

struct ColumnSpec: Codable, Hashable {
    let key: String
    let title: String?
    let type: String // text | number | hours | date | enum
    let role: String? // title | subtitle | caption | warning | trailing | badge
    let options: [EnumOption]?
    let fallback: String?

    func option(_ value: String) -> EnumOption? { options?.first { $0.value == value } }
}

struct EnumOption: Codable, Hashable {
    let value: String
    let label: String?
    let color: String?

    var title: String { label ?? value }
}

struct StatSpec: Codable, Hashable {
    let key: String
    let title: String
    let type: String // number | hours | text
}

struct FilterSpec: Codable, Hashable {
    let key: String
    let `default`: [String]
}

struct OperationSpec: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let icon: String?
    let kind: String // command | claude
    let scope: String // module | row
    let inputs: [InputSpec]?
    let confirm: String?
    let when: [Condition]?
    let destructive: Bool?
    let params: [String]

    struct Condition: Codable, Hashable {
        let field: String
        let values: [String]
    }

    func applies(to row: Row) -> Bool {
        (when ?? []).allSatisfy { $0.values.contains(row.value($0.field).text) }
    }
}

struct InputSpec: Codable, Hashable {
    let key: String
    let title: String
    let type: String // text | multiline
    let `default`: String?
}

/// Any JSON value in a module's rows or summary.
enum JSONValue: Decodable, Hashable {
    case string(String), number(Double), bool(Bool), null, other(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .other(a.map(\.text).joined(separator: ", ")) }
        else { self = .other("…") }
    }

    /// Raw text, as the server compares it (e.g. for `when`).
    var text: String {
        switch self {
        case .string(let s), .other(let s): s
        case .number(let n): n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): b ? "true" : "false"
        case .null: ""
        }
    }

    var number: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
}

typealias Row = [String: JSONValue]

extension Dictionary where Key == String, Value == JSONValue {
    var rowID: String { self["id"]?.text ?? "" }
    func value(_ key: String) -> JSONValue { self[key] ?? .null }
}

struct ViewData: Decodable {
    let rows: [Row]
    let summary: [String: JSONValue]?
    let notes: [String]?
    let fetchedAt: Date
    let stale: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case rows, summary, notes, stale, error
        case fetchedAt = "fetched_at"
    }
}

/// Body of POST /api/modules/{id}/ops/{op}.
struct OperationRequest: Encodable {
    let view: String
    let params: [String: String]
    var rowID: String?
    var inputs: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case view, params, inputs
        case rowID = "row_id"
    }
}

extension JSONDecoder {
    /// Module data: keys are the module's own (snake_case stays as is).
    static let moduleData: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = JSONDecoder.api.dateDecodingStrategy
        return d
    }()
}

enum ValueFormat {
    static func text(_ value: JSONValue, _ column: ColumnSpec) -> String {
        switch column.type {
        case "hours": value.number.map(hours) ?? value.text
        case "number": value.number.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? value.text
        case "date": date(value.text)
        case "enum": column.option(value.text)?.title ?? value.text
        default: value.text
        }
    }

    static func stat(_ value: JSONValue, type: String) -> String {
        switch type {
        case "hours": value.number.map(hours) ?? "–"
        case "number": value.number.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "–"
        default: value == .null ? "–" : value.text
        }
    }

    static func hours(_ h: Double) -> String { h.formatted(.number.precision(.fractionLength(0...2))) + " h" }

    /// "2026-10-02" → "Fri 2 Oct"
    static func date(_ s: String) -> String {
        guard let d = try? Date(s, strategy: .iso8601.year().month().day()) else { return s }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Fills {row.key} in an input default.
    static func fill(_ template: String, row: Row) -> String {
        var out = template
        for (k, v) in row { out = out.replacingOccurrences(of: "{row.\(k)}", with: v.text) }
        return out
    }
}

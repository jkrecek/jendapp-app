import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct UploadFile {
    let name: String
    let url: URL // local file to stream from
}

/// One server-sent event: `name` is "message" for Claude stream-json lines, "end" for the final job.
struct ServerEvent {
    let name: String
    let data: Data
}

struct APIClient {
    let baseURL: URL
    let token: String

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: baseURL.appending(path: path))
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    private func send<T: Decodable>(_ r: URLRequest) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: r)
        try Self.check(resp, data)
        return try JSONDecoder.api.decode(T.self, from: data)
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError(message: msg ?? "HTTP \(http.statusCode)")
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var r = request(path)
        if !query.isEmpty {
            r.url = r.url?.appending(queryItems: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        return try await send(r)
    }

    func post<T: Decodable>(_ path: String, json: [String: String]) async throws -> T {
        var r = request(path, method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(json)
        return try await send(r)
    }

    // MARK: Endpoints

    func modules() async throws -> [ModuleInfo] { try await get("api/modules") }
    func sessions(module: String) async throws -> [SessionInfo] { try await get("api/modules/\(module)/sessions") }
    func messages(module: String, session: String) async throws -> [SessionMessage] {
        try await get("api/modules/\(module)/sessions/\(session)")
    }
    func inbox() async throws -> [InboxItem] { try await get("api/inbox") }
    func jobs(module: String? = nil) async throws -> [Job] {
        try await get("api/jobs", query: module.map { ["module": $0] } ?? [:])
    }
    func job(_ id: String) async throws -> Job { try await get("api/jobs/\(id)") }

    func assign(item: String, module: String) async throws -> InboxItem {
        try await post("api/inbox/\(item)/assign", json: ["module_id": module])
    }

    func chat(module: String, message: String, session: String?) async throws -> Job {
        var body = ["message": message]
        if let session { body["session_id"] = session }
        return try await post("api/modules/\(module)/chat", json: body)
    }

    /// Multipart upload, built in a temp file so large files never sit in memory
    /// (Share extensions have a tight memory limit).
    func upload(_ files: [UploadFile]) async throws -> [InboxItem] {
        let boundary = "jendapp-\(UUID().uuidString)"
        let body = FileManager.default.temporaryDirectory.appending(path: "upload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: body) }
        FileManager.default.createFile(atPath: body.path(), contents: nil)
        let out = try FileHandle(forWritingTo: body)
        for f in files {
            let name = f.name.replacingOccurrences(of: "\"", with: "'")
            try out.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            let input = try FileHandle(forReadingFrom: f.url)
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                try out.write(contentsOf: chunk)
            }
            try input.close()
            try out.write(contentsOf: Data("\r\n".utf8))
        }
        try out.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
        try out.close()

        var r = request("api/inbox", method: "POST")
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 300
        let (data, resp) = try await URLSession.shared.upload(for: r, fromFile: body)
        try Self.check(resp, data)
        return try JSONDecoder.api.decode([InboxItem].self, from: data)
    }

    /// Streams a job's events (replayed from the start) until the server sends "end".
    func events(job: String) -> AsyncThrowingStream<ServerEvent, Error> {
        var r = request("api/jobs/\(job)/events")
        r.timeoutInterval = 900 // tool runs can be quiet for a while
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: r)
                    try Self.check(resp, Data())
                    // The server writes one data line per event; `event:` precedes only "end".
                    var name = "message"
                    for try await line in bytes.lines {
                        if let n = line.stripping("event: ") {
                            name = n
                        } else if let d = line.stripping("data: ") {
                            continuation.yield(ServerEvent(name: name, data: Data(d.utf8)))
                            name = "message"
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private extension String {
    func stripping(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

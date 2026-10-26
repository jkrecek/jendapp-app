import SwiftUI
import UniformTypeIdentifiers

/// Uploads whatever was shared into the jendapp inbox and shows where each file was routed.
struct ShareView: View {
    let providers: [NSItemProvider]
    let finish: () -> Void

    private enum Phase {
        case working(String)
        case done([InboxItem])
        case failed(String)
    }

    @State private var phase = Phase.working("Preparing…")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Send to Jendapp").font(.headline)
                Spacer()
                Button("Done", action: finish)
                    .keyboardShortcut(.defaultAction)
            }
            switch phase {
            case .working(let msg):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(msg).foregroundStyle(.secondary)
                }
            case .done(let items):
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(item.filename, systemImage: symbol(item.status))
                            .lineLimit(1).truncationMode(.middle)
                        Text(describe(item)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 160)
        .task { await upload() }
    }

    private func upload() async {
        guard let client = AppConfig.client else {
            phase = .failed("Open Jendapp and pair it with the server first.")
            return
        }
        let dir = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var files: [UploadFile] = []
            for p in providers {
                if let f = try await Self.loadFile(p, into: dir) { files.append(f) }
            }
            guard !files.isEmpty else {
                phase = .failed("Nothing to upload — only files can be shared for now.")
                return
            }
            phase = .working("Uploading \(files.count) file\(files.count == 1 ? "" : "s")…")
            phase = .done(try await client.upload(files))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Copies the provider's file representation into `dir` (the provided URL is
    /// only valid inside the callback).
    nonisolated private static func loadFile(_ p: NSItemProvider, into dir: URL) async throws -> UploadFile? {
        guard let type = p.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .data) == true || UTType($0)?.conforms(to: .fileURL) == true
        }) else { return nil }
        let suggested = p.suggestedName
        return try await withCheckedThrowingContinuation { cont in
            _ = p.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    cont.resume(throwing: error ?? APIError(message: "Could not read shared item"))
                    return
                }
                var name = url.lastPathComponent
                if name.hasPrefix(".") || name.isEmpty, let suggested {
                    name = suggested
                }
                let dest = dir.appending(path: UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: UploadFile(name: name, url: dest))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func symbol(_ status: String) -> String {
        switch status {
        case "routed": "checkmark.circle.fill"
        case "skipped": "equal.circle"
        case "failed": "xmark.octagon"
        default: "tray"
        }
    }

    private func describe(_ item: InboxItem) -> String {
        switch item.status {
        case "routed": "Sent to \(item.moduleId ?? "module")"
        case "skipped": "Already in \(item.moduleId ?? "module")"
        case "failed": item.error ?? "Failed"
        default: "In inbox — pick a module in the app"
        }
    }
}

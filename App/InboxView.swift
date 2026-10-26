import SwiftUI

struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [InboxItem] = []
    @State private var error: String?
    @State private var importing = false
    @State private var uploading = false

    var body: some View {
        NavigationStack {
            List(items) { item in
                InboxRow(item: item, modules: model.modules) { moduleID in
                    Task { await assign(item, to: moduleID) }
                }
            }
            .overlay { LoadState(error: error, isEmpty: items.isEmpty, emptyText: "Inbox is empty") }
            .navigationTitle("Inbox")
            .refreshable { await load() }
            .task { await load() }
            .toolbar {
                Button("Import files", systemImage: "square.and.arrow.down") { importing = true }
                    .disabled(uploading)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await upload(urls) } }
            }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            items = try await client.inbox()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func upload(_ urls: [URL]) async {
        guard let client = model.client else { return }
        uploading = true
        defer { uploading = false }
        let scoped = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer { scoped.forEach { if $0.1 { $0.0.stopAccessingSecurityScopedResource() } } }
        do {
            _ = try await client.upload(urls.map { UploadFile(name: $0.lastPathComponent, url: $0) })
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func assign(_ item: InboxItem, to moduleID: String) async {
        guard let client = model.client else { return }
        do {
            _ = try await client.assign(item: item.id, module: moduleID)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem
    let modules: [ModuleInfo]
    let assign: (String) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.status == "pending" {
                Menu("Assign") {
                    ForEach(modules) { m in
                        Button(m.name, systemImage: m.symbol) { assign(m.id) }
                    }
                }
                .fixedSize()
            } else {
                Image(systemName: icon).foregroundStyle(item.status == "failed" ? .red : .secondary)
            }
        }
    }

    private var subtitle: String {
        let when = item.createdAt.formatted(.relative(presentation: .named))
        switch item.status {
        case "routed": return "\(item.moduleId ?? "") · \(when)"
        case "skipped": return "already in \(item.moduleId ?? "module") · \(when)"
        case "failed": return item.error ?? "failed"
        default: return "needs a module · \(when)"
        }
    }

    private var icon: String {
        switch item.status {
        case "routed": "checkmark.circle"
        case "skipped": "equal.circle"
        default: "xmark.octagon"
        }
    }
}

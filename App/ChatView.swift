import SwiftUI

struct ChatItem: Identifiable {
    enum Role { case user, assistant, tool, notice }
    let id = UUID()
    let role: Role
    var text: String
}

/// Chat with Claude running in a module's folder. Each message is one
/// `claude -p --resume` run on the server, streamed back over SSE.
@Observable
final class ChatModel {
    let module: ModuleInfo
    private(set) var sessionID: String?
    var items: [ChatItem] = []
    var isRunning = false
    /// Sent once when the view first appears (module actions).
    var pendingPrompt: String?
    /// Action follow-up, offered after a run finishes successfully.
    var confirm: ActionConfirm?
    private(set) var canConfirm = false

    private var toolItems: [String: Int] = [:] // tool_use id → item index

    init(module: ModuleInfo, sessionID: String?) {
        self.module = module
        self.sessionID = sessionID
    }

    func loadHistory(_ client: APIClient) async {
        guard let sessionID, items.isEmpty else { return }
        do {
            items = try await client.messages(module: module.id, session: sessionID).map {
                ChatItem(role: $0.role == "user" ? .user : .assistant, text: $0.text)
            }
        } catch {
            items.append(ChatItem(role: .notice, text: error.localizedDescription))
        }
    }

    func send(_ text: String, client: APIClient) async {
        canConfirm = false
        items.append(ChatItem(role: .user, text: text))
        isRunning = true
        defer { isRunning = false }
        do {
            let job = try await client.chat(module: module.id, message: text, session: sessionID)
            sessionID = job.sessionId
            try await follow(job.id, client: client)
        } catch {
            items.append(ChatItem(role: .notice, text: error.localizedDescription))
        }
    }

    /// Attaches to a running job (e.g. an on_import run) and renders its output.
    func follow(_ jobID: String, client: APIClient) async throws {
        toolItems = [:]
        for try await event in client.events(job: jobID) {
            if event.name == "end" {
                if let job = try? JSONDecoder.api.decode(Job.self, from: event.data) { finish(job) }
            } else {
                handle(event.data)
            }
        }
    }

    private func handle(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "stream_event":
            guard let ev = obj["event"] as? [String: Any], let evType = ev["type"] as? String else { return }
            if evType == "content_block_delta",
               let delta = ev["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
               let t = delta["text"] as? String {
                appendAssistant(t)
            } else if evType == "content_block_start",
                      let block = ev["content_block"] as? [String: Any], block["type"] as? String == "tool_use",
                      let name = block["name"] as? String, let id = block["id"] as? String {
                toolItems[id] = items.count
                items.append(ChatItem(role: .tool, text: name))
            }
        case "assistant":
            // Complete message: fill in tool call details (inputs arrive in full here).
            guard let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { return }
            for block in content where block["type"] as? String == "tool_use" {
                guard let id = block["id"] as? String, let idx = toolItems[id],
                      let name = block["name"] as? String else { continue }
                items[idx].text = Self.describeTool(name, block["input"] as? [String: Any] ?? [:])
            }
        default:
            break
        }
    }

    private func appendAssistant(_ t: String) {
        if let last = items.indices.last, items[last].role == .assistant {
            items[last].text += t
        } else {
            items.append(ChatItem(role: .assistant, text: t))
        }
    }

    private func finish(_ job: Job) {
        canConfirm = confirm != nil && job.status == "done"
        if job.status == "failed" {
            items.append(ChatItem(role: .notice, text: "Failed: \(job.error ?? "unknown error")"))
        }
        if let denials = job.denials {
            items.append(ChatItem(role: .notice, text: "Blocked tool calls (not in allowed_tools): \(denials)"))
        }
    }

    private static func describeTool(_ name: String, _ input: [String: Any]) -> String {
        let detail = (input["command"] ?? input["file_path"] ?? input["pattern"] ?? input["description"]) as? String
        guard let detail else { return name }
        return "\(name): \(detail.count > 120 ? String(detail.prefix(120)) + "…" : detail)"
    }
}

struct ChatView: View {
    @Environment(AppModel.self) private var app
    @State private var chat: ChatModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(module: ModuleInfo, sessionID: String?, prompt: String? = nil, confirm: ActionConfirm? = nil) {
        let chat = ChatModel(module: module, sessionID: sessionID)
        chat.pendingPrompt = prompt
        chat.confirm = confirm
        _chat = State(initialValue: chat)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chat.items) { MessageRow(item: $0) }
                    if chat.isRunning {
                        ProgressView().controlSize(.small).padding(.leading, 4)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: chat.items.last?.text) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(chat.module.name)
        .task {
            guard let client = app.client else { return }
            await chat.loadHistory(client)
            if let prompt = chat.pendingPrompt {
                chat.pendingPrompt = nil
                await chat.send(prompt, client: client)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if chat.canConfirm, let confirm = chat.confirm, !chat.isRunning {
                Button {
                    guard let client = app.client else { return }
                    Task { await chat.send(confirm.prompt, client: client) }
                } label: {
                    Label(confirm.title, systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            composerField
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message \(chat.module.name)…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.quaternary, in: .rect(cornerRadius: 18))
                .focused($focused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isRunning)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isRunning, let client = app.client else { return }
        draft = ""
        Task { await chat.send(text, client: client) }
    }
}

struct MessageRow: View {
    let item: ChatItem

    var body: some View {
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 14))
            }
        case .assistant:
            Text(markdown(item.text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tool:
            Label(item.text, systemImage: "wrench.and.screwdriver")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        case .notice:
            Label(item.text, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

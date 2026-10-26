import SwiftUI

/// Claude runs (chats and on_import jobs), newest first.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var jobs: [Job] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List(jobs) { job in
                NavigationLink(value: Route.job(job)) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(model.module(job.moduleId)?.name ?? job.moduleId).font(.headline)
                            Text(job.kind).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            StatusBadge(status: job.status)
                        }
                        Text(job.result ?? job.error ?? job.prompt)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        Text(job.createdAt, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .overlay { LoadState(error: error, isEmpty: jobs.isEmpty, emptyText: "No activity yet") }
            .navigationTitle("Activity")
            .refreshable { await load() }
            .task { await load() }
            .appRoutes()
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            jobs = try await client.jobs()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case "done": .green
        case "failed": .red
        case "running": .blue
        default: .secondary
        }
    }
}

struct JobView: View {
    let job: Job
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !job.isFinished, let module = model.module(job.moduleId) {
                // Still running: attach to the live stream.
                LiveJobView(module: module, job: job)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            StatusBadge(status: job.status)
                            if let cost = job.costUsd {
                                Text(cost, format: .currency(code: "USD")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let result = job.result { Text(markdown(result)).textSelection(.enabled) }
                        if let error = job.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                        if let denials = job.denials { Label("Blocked: \(denials)", systemImage: "hand.raised").font(.caption) }
                        DisclosureGroup("Prompt") { Text(job.prompt).font(.callout).textSelection(.enabled) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
        }
        .navigationTitle(model.module(job.moduleId)?.name ?? job.moduleId)
        .toolbar {
            if let module = model.module(job.moduleId) {
                NavigationLink(value: Route.chat(module, sessionID: job.sessionId)) {
                    Label("Continue in chat", systemImage: "bubble.left.and.text.bubble.right")
                }
            }
        }
    }
}

private struct LiveJobView: View {
    @Environment(AppModel.self) private var app
    @State private var chat: ChatModel
    let job: Job

    init(module: ModuleInfo, job: Job) {
        self.job = job
        _chat = State(initialValue: ChatModel(module: module, sessionID: job.sessionId))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(chat.items) { MessageRow(item: $0) }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .task {
            guard let client = app.client else { return }
            try? await chat.follow(job.id, client: client)
        }
    }
}

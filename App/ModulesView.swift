import SwiftUI

struct ModulesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.modules) { m in
                NavigationLink(value: Route.module(m)) {
                    Label(m.name, systemImage: m.symbol)
                }
                .disabled(!m.available)
            }
            .overlay { LoadState(error: model.error, isEmpty: model.modules.isEmpty, emptyText: "No modules") }
            .navigationTitle("Modules")
            .refreshable { await model.loadModules() }
            .toolbar {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.loadModules() } }
            }
            .appRoutes()
        }
    }
}

/// A module: start a new chat or continue one of its Claude sessions
/// (including sessions started from the terminal).
struct ModuleView: View {
    let module: ModuleInfo
    @Environment(AppModel.self) private var model
    @State private var sessions: [SessionInfo] = []
    @State private var error: String?
    @State private var launch: Route?

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.chat(module, sessionID: nil)) {
                    Label("New chat", systemImage: "plus.bubble")
                }
                ForEach(module.actions ?? []) { a in
                    if a.input == "month" {
                        Menu {
                            ForEach(Self.recentMonths, id: \.id) { month in
                                Button(month.label) { launch = route(a, month: month.id) }
                            }
                        } label: {
                            Label(a.title, systemImage: a.icon ?? "bolt")
                        }
                    } else {
                        NavigationLink(value: route(a, month: nil)) {
                            Label(a.title, systemImage: a.icon ?? "bolt")
                        }
                    }
                }
            }
            Section("Sessions") {
                ForEach(sessions) { s in
                    NavigationLink(value: Route.chat(module, sessionID: s.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title.isEmpty ? "Untitled" : s.title).lineLimit(2)
                            Text(s.updatedAt, format: .relative(presentation: .named))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay { LoadState(error: error, isEmpty: false, emptyText: "") }
        .navigationTitle(module.name)
        .navigationDestination(item: $launch) { route in
            if case .action(let m, let prompt, let confirm) = route {
                ChatView(module: m, sessionID: nil, prompt: prompt, confirm: confirm)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func route(_ a: ModuleAction, month: String?) -> Route {
        let r = a.resolved(month: month)
        return .action(module, prompt: r.prompt, confirm: r.confirm)
    }

    /// This month and the two before it, as ("2026-10", "October 2026").
    private static var recentMonths: [(id: String, label: String)] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        return (0..<3).map { back in
            let d = cal.date(byAdding: .month, value: -back, to: start)!
            let c = cal.dateComponents([.year, .month], from: d)
            return (String(format: "%04d-%02d", c.year!, c.month!), d.formatted(.dateTime.month(.wide).year()))
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            sessions = try await client.sessions(module: module.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

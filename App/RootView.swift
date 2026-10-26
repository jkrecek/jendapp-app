import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isPaired {
            TabView {
                Tab("Modules", systemImage: "square.grid.2x2") { ModulesView() }
                Tab("Inbox", systemImage: "tray") { InboxView() }
                Tab("Activity", systemImage: "bolt.horizontal") { ActivityView() }
                Tab("Settings", systemImage: "gear") { NavigationStack { SettingsView() } }
            }
            .tabViewStyle(.sidebarAdaptable)
            .task { await model.loadModules() }
        } else {
            NavigationStack { SettingsView() }
        }
    }
}

enum Route: Hashable {
    case module(ModuleInfo)
    case chat(ModuleInfo, sessionID: String?)
    case action(ModuleInfo, prompt: String, confirm: ActionConfirm?)
    case job(Job)
}

extension View {
    func appRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .module(let m): ModuleView(module: m)
            case .chat(let m, let sid): ChatView(module: m, sessionID: sid)
            case .action(let m, let prompt, let confirm): ChatView(module: m, sessionID: nil, prompt: prompt, confirm: confirm)
            case .job(let j): JobView(job: j)
            }
        }
    }
}

/// Shared error/empty presentation for list screens.
struct LoadState: View {
    let error: String?
    let isEmpty: Bool
    let emptyText: String

    var body: some View {
        if let error {
            ContentUnavailableView("Can't reach server", systemImage: "wifi.exclamationmark", description: Text(error))
        } else if isEmpty {
            ContentUnavailableView(emptyText, systemImage: "tray")
        }
    }
}

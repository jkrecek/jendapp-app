import SwiftUI

@main
struct JendappApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in
                    if AppConfig.applyPairingURL(url) {
                        model.reconfigure()
                    }
                }
        }
    }
}

/// App-wide state: connection + module list.
@Observable
final class AppModel {
    var client: APIClient? = AppConfig.client
    var modules: [ModuleInfo] = []
    var error: String?

    var isPaired: Bool { client != nil }

    func reconfigure() {
        client = AppConfig.client
        modules = []
        Task { await loadModules() }
    }

    func loadModules() async {
        guard let client else { return }
        do {
            modules = try await client.modules()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func module(_ id: String) -> ModuleInfo? { modules.first { $0.id == id } }
}

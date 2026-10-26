import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var server = AppConfig.serverURL?.absoluteString ?? ""
    @State private var token = AppConfig.token ?? ""
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $server, prompt: Text("https://host.tailnet.ts.net:8443"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                SecureField("Device token", text: $token)
            } header: {
                Text("Server")
            } footer: {
                Text("Run `jendapp pair <device>` on the server and open the printed jendapp://pair link on this device, or paste the values here.")
            }
            Section {
                Button("Save & test connection") { Task { await save() } }
                    .disabled(URL(string: server)?.scheme == nil || token.isEmpty)
                if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: model.isPaired) {
            server = AppConfig.serverURL?.absoluteString ?? ""
            token = AppConfig.token ?? ""
        }
    }

    private func save() async {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)) else { return }
        let client = APIClient(baseURL: url, token: token.trimmingCharacters(in: .whitespaces))
        status = "Connecting…"
        do {
            let modules = try await client.modules()
            AppConfig.serverURL = client.baseURL
            AppConfig.token = client.token
            model.reconfigure()
            status = "Connected — \(modules.count) module\(modules.count == 1 ? "" : "s")."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }
}

import SwiftUI

struct GeneralSettingsPane: View {
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    SettingsRowLabel(
                        "Open at Login",
                        subtitle: "Start CodexN automatically when you sign in."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
        .onChange(of: launchAtLogin) { _, enabled in
            updateLaunchAtLogin(enabled)
        }
        .alert("CodexN Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginManager.isEnabled
        } catch {
            errorMessage = String(describing: error)
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
    }
}

import CodexNCore
import SwiftUI

enum AddProfileSelection: String, CaseIterable, Identifiable {
    case importDefault
    case oauth
    case apiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .importDefault: "Import Default"
        case .oauth: "OAuth Login"
        case .apiKey: "API Key"
        }
    }

    var subtitle: String {
        switch self {
        case .importDefault: "Copy the current system Codex profile."
        case .oauth: "Create an empty isolated profile."
        case .apiKey: "Create a provider config with injected API key."
        }
    }

    var symbol: String {
        switch self {
        case .importDefault: "tray.and.arrow.down"
        case .oauth: "person.crop.circle"
        case .apiKey: "key"
        }
    }
}

struct ProfilesSettingsPane: View {
    let store: ProfileStore
    let onCancel: () -> Void
    let onProfilesChanged: () -> Void

    @State private var profiles: [Profile] = []
    @State private var selection: AddProfileSelection = .oauth
    @State private var id = ""
    @State private var name = ""
    @State private var provider = ""
    @State private var model = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var pendingRemoval: Profile?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Saved Profiles") {
                if profiles.isEmpty {
                    Text("No profiles")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        HStack(spacing: 10) {
                            SettingsIconChip(
                                systemImage: profile.apiKeyEnvName == nil ? "person.crop.circle" : "key",
                                color: profile.apiKeyEnvName == nil ? .blue : .orange
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                Text(profile.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                pendingRemoval = profile
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Remove Profile")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Add Profile") {
                Picker(selection: $selection) {
                    ForEach(AddProfileSelection.allCases) { item in
                        Text(item.title).tag(item)
                    }
                } label: {
                    SettingsRowLabel("Mode", subtitle: selection.subtitle)
                }
                .pickerStyle(.menu)

                LabeledContent("Profile ID") {
                    TextField("", text: $id)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }

                LabeledContent("Display Name") {
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
            }

            if selection == .apiKey {
                Section("Provider") {
                    LabeledContent("Model Provider") {
                        TextField("", text: $provider)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    LabeledContent("Model Name") {
                        TextField("", text: $model)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    LabeledContent("Base URL") {
                        TextField("", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    LabeledContent("API Key") {
                        SecureField("", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Create") {
                        createProfile()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadProfiles)
        .alert("Remove Profile", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("Remove", role: .destructive) {
                removePendingProfile()
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text(removeConfirmationMessage)
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

    private var removeConfirmationMessage: String {
        guard let pendingRemoval else { return "" }
        return "Remove \(pendingRemoval.id) from CodexN? Files remain on disk."
    }

    private func loadProfiles() {
        do {
            profiles = try store.listProfiles()
        } catch {
            profiles = []
            errorMessage = String(describing: error)
        }
    }

    private func createProfile() {
        do {
            let profileID = trimmed(id)
            let displayName = trimmed(name).isEmpty ? profileID : trimmed(name)
            switch selection {
            case .importDefault:
                _ = try store.importDefaultProfile(id: profileID, name: displayName)
            case .oauth:
                _ = try store.createProfile(id: profileID, name: displayName)
            case .apiKey:
                _ = try store.createAPIKeyProfile(
                    id: profileID,
                    name: displayName,
                    provider: trimmed(provider),
                    model: trimmed(model),
                    baseURL: trimmed(baseURL),
                    apiKey: apiKey
                )
            }
            resetAddForm()
            loadProfiles()
            onProfilesChanged()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func removePendingProfile() {
        guard let profile = pendingRemoval else { return }
        do {
            _ = try store.deleteProfile(id: profile.id)
            pendingRemoval = nil
            loadProfiles()
            onProfilesChanged()
        } catch {
            pendingRemoval = nil
            errorMessage = String(describing: error)
        }
    }

    private func resetAddForm() {
        id = ""
        name = ""
        provider = ""
        model = ""
        baseURL = ""
        apiKey = ""
        selection = .oauth
    }
}

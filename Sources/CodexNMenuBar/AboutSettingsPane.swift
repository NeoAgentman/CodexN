import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    private let appName = "CodexN"
    private let repositoryURL = URL(string: "https://github.com/NeoAgentman/CodexN")!

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(spacing: 3) {
                        Text(appName)
                            .font(.title2.weight(.semibold))
                        Text("Codex profile launcher")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }

            Section("Version") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
                LabeledContent("Built", value: buildDate)
            }

            Section("Project") {
                Button {
                    NSWorkspace.shared.open(repositoryURL)
                } label: {
                    HStack {
                        SettingsRowLabel("GitHub", subtitle: "NeoAgentman/CodexN")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(repositoryURL.absoluteString)
                .accessibilityLabel("Open GitHub repository")
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        infoValue("CFBundleShortVersionString", fallback: "Development")
    }

    private var buildNumber: String {
        infoValue("CFBundleVersion", fallback: "Development")
    }

    private var buildDate: String {
        infoValue("CodexNBuildDate", fallback: "Development build")
    }

    private func infoValue(_ key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            return fallback
        }
        return value
    }
}

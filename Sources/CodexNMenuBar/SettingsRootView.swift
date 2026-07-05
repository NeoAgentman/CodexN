import CodexNCore
import SwiftUI

struct SettingsRootView: View {
    let store: ProfileStore
    let initialSelection: SettingsPane
    let onClose: () -> Void
    let onComplete: () -> Void

    @State private var selection: SettingsPane

    init(
        store: ProfileStore,
        initialSelection: SettingsPane,
        onClose: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.store = store
        self.initialSelection = initialSelection
        self.onClose = onClose
        self.onComplete = onComplete
        self._selection = State(initialValue: initialSelection)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 200)
                .background(.bar)

            Divider()

            SettingsDetailPane {
                switch selection {
                case .general:
                    GeneralSettingsPane()
                case .profiles:
                    ProfilesSettingsPane(
                        store: store,
                        onCancel: onClose,
                        onProfilesChanged: onComplete
                    )
                case .about:
                    AboutSettingsPane()
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 480, idealHeight: 520)
        .onAppear {
            selection = initialSelection
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CodexN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ForEach(SettingsPane.allCases) { pane in
                Button {
                    selection = pane
                } label: {
                    HStack(spacing: 9) {
                        SettingsIconChip(systemImage: pane.symbol, color: pane.color)
                        Text(pane.title)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection == pane ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()
        }
    }
}

struct SettingsDetailPane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

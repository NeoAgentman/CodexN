import SwiftUI

struct ProfileMenuHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CodexN")
                .font(.headline)
            Text("Switch Codex profiles and providers.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 280, alignment: .leading)
    }
}

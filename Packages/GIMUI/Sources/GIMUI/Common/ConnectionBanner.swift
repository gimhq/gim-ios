import GIMClientKit
import SwiftUI

/// Slim status bar shown while the client is offline, connecting or catching up.
public struct ConnectionBanner: View {
    let state: ConnectionState

    public init(state: ConnectionState) {
        self.state = state
    }

    public var body: some View {
        switch state {
        case .connected:
            EmptyView()
        case .syncing:
            banner {
                ProgressView().controlSize(.small)
                Text("Updating…", tableName: "Common", bundle: .module)
            }
        case .connecting:
            banner {
                ProgressView().controlSize(.small)
                Text("Connecting…", tableName: "Common", bundle: .module)
            }
        case .offline:
            banner {
                Image(systemName: "wifi.slash")
                Text("Waiting for internet", tableName: "Common", bundle: .module)
            }
        }
    }

    private func banner(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8, content: content)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            Divider()
        }
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    VStack {
        ConnectionBanner(state: .connecting)
        ConnectionBanner(state: .syncing)
        ConnectionBanner(state: .offline)
    }
}

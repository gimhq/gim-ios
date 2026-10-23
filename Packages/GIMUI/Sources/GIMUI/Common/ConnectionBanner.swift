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
                Text("Updating…")
            }
        case .connecting:
            banner {
                ProgressView().controlSize(.small)
                Text("Connecting…")
            }
        case .offline:
            banner {
                Image(systemName: "wifi.slash")
                Text("Waiting for network")
            }
        }
    }

    private func banner(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8, content: content)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.bar)
            .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack {
        ConnectionBanner(state: .connecting)
        ConnectionBanner(state: .syncing)
        ConnectionBanner(state: .offline)
    }
}

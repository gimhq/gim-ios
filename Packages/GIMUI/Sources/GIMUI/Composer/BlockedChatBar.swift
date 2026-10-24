import SwiftUI

/// Replaces the composer while the other user of a direct chat is blocked; the timeline stays readable above it.
struct BlockedChatBar: View {
    let unblock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("You blocked this person.", tableName: "Chat", bundle: .module)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "Unblock", table: "Chat", bundle: .module), action: unblock)
                .accessibilityIdentifier("chat.unblock")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.blocked")
    }
}

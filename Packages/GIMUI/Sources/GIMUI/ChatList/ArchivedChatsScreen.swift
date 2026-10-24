import GIMFeatures
import SwiftUI

/// The archived chats, opened from the chat list's "Archived chats" row. Closes once nothing is archived.
struct ArchivedChatsScreen: View {
    let viewModel: ChatListViewModel
    let onOpen: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(viewModel.archivedRows) { row in
            ChatListRow(row: row, viewModel: viewModel, onOpen: onOpen)
        }
        .listStyle(.plain)
        .navigationTitle(Text("Archived chats", tableName: "Chat", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Done", tableName: "Common", bundle: .module)
                }
                .accessibilityIdentifier("chatList.archived.done")
            }
        }
        .chatActionErrorAlert(viewModel)
        .onChange(of: viewModel.hasArchived) { _, hasArchived in
            if !hasArchived { dismiss() }
        }
    }
}

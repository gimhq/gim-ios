import GIMFeatures
import SwiftUI

/// A tappable chat row with its swipe actions and context menu: pin, mute and archive. Shared by the chat list and
/// the archived chats.
struct ChatListRow: View {
    let row: ChatRow
    let viewModel: ChatListViewModel
    let onOpen: (String) -> Void

    var body: some View {
        Button {
            onOpen(row.id)
        } label: {
            ChatRowView(row: row, subtitle: viewModel.subtitle(for: row), status: viewModel.lastMessageStatus(for: row))
        }
        .accessibilityIdentifier("chatList.row")
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .swipeActions(edge: .leading) {
            pinButton
        }
        .swipeActions(edge: .trailing) {
            archiveButton
            muteControl
        }
        .contextMenu {
            pinButton
            muteControl
            archiveButton
        }
    }

    private var pinButton: some View {
        Button {
            Task { await viewModel.setPinned(row, !row.isPinned) }
        } label: {
            if row.isPinned {
                Label(String(localized: "Unpin", table: "Chat", bundle: .module), systemImage: "pin.slash")
            } else {
                Label(String(localized: "Pin", table: "Chat", bundle: .module), systemImage: "pin")
            }
        }
        .tint(.orange)
        .accessibilityIdentifier("chatList.row.pin")
    }

    @ViewBuilder
    private var muteControl: some View {
        if row.isMuted {
            Button {
                Task { await viewModel.unmute(row) }
            } label: {
                Label(String(localized: "Unmute", table: "Chat", bundle: .module), systemImage: "bell")
            }
            .tint(.indigo)
            .accessibilityIdentifier("chatList.row.unmute")
        } else {
            Menu {
                ForEach(ChatMuteOption.allCases, id: \.self) { option in
                    Button(option.title) {
                        Task { await viewModel.mute(row, option) }
                    }
                    .accessibilityIdentifier("chatList.row.mute.\(String(describing: option))")
                }
            } label: {
                Label(String(localized: "Mute", table: "Chat", bundle: .module), systemImage: "bell.slash")
            }
            .tint(.indigo)
            .accessibilityIdentifier("chatList.row.mute")
        }
    }

    private var archiveButton: some View {
        Button {
            Task { await viewModel.setArchived(row, !row.isArchived) }
        } label: {
            if row.isArchived {
                Label(String(localized: "Unarchive", table: "Chat", bundle: .module), systemImage: "tray.and.arrow.up")
            } else {
                Label(String(localized: "Archive", table: "Chat", bundle: .module), systemImage: "archivebox")
            }
        }
        .tint(.gray)
        .accessibilityIdentifier("chatList.row.archive")
    }
}

extension View {
    /// Shows `ChatListViewModel.actionErrorMessage` while `isActive`.
    func chatActionErrorAlert(_ viewModel: ChatListViewModel, isActive: Bool = true) -> some View {
        alert(
            Text("Something went wrong", tableName: "Common", bundle: .module),
            isPresented: Binding(
                get: { isActive && viewModel.actionErrorMessage != nil },
                set: { if !$0 { viewModel.dismissActionError() } })
        ) {
            Button(String(localized: "OK", table: "Common", bundle: .module), role: .cancel) {}
        } message: {
            Text(viewModel.actionErrorMessage ?? "")
        }
    }
}

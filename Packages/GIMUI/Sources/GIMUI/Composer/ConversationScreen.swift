import GIMClientKit
import GIMFeatures
import SwiftUI

/// A chat with its composer and the full message menu (reply, react, copy, edit, delete with confirmation, retry).
public struct ConversationScreen: View {
    private let client: any GimClientAPI
    private let chatId: String
    private let drafts: ComposerDrafts
    private let leavingChats: LeavingChats?

    @State private var actions: MessageActionsViewModel

    /// - Parameters:
    ///   - drafts: unsent text per chat, shared by all chats of the session.
    ///   - leavingChats: the chats the user is leaving, shared by all screens of the session.
    public init(client: any GimClientAPI, chatId: String, drafts: ComposerDrafts, leavingChats: LeavingChats? = nil) {
        self.client = client
        self.chatId = chatId
        self.drafts = drafts
        self.leavingChats = leavingChats
        _actions = State(initialValue: MessageActionsViewModel(client: client, chatId: chatId))
    }

    public var body: some View {
        ChatScreen(
            client: client, chatId: chatId, leavingChats: leavingChats,
            contextMenuProvider: { [actions] message, context in
                MessageContextMenu.menu(for: message, context: context, actions: actions)
            }
        ) { _, replyingTo, editing in
            ComposerView(
                client: client, chatId: chatId, drafts: drafts, leavingChats: leavingChats, replyingTo: replyingTo,
                editing: editing)
        }
        .confirmationDialog(
            "Delete this message for everyone?",
            isPresented: Binding(
                get: { actions.pendingDelete != nil },
                set: { if !$0 { actions.cancelDelete() } }),
            titleVisibility: .visible,
            presenting: actions.pendingDelete
        ) { message in
            Button("Delete", role: .destructive) {
                Task { await actions.delete(message) }
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { actions.errorMessage != nil },
                set: { if !$0 { actions.dismissError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actions.errorMessage ?? "")
        }
    }
}

#Preview {
    NavigationStack {
        ConversationScreen(
            client: FakeGimClient.demo(), chatId: FakeGimClient.demoGroupChatId, drafts: ComposerDrafts())
    }
}

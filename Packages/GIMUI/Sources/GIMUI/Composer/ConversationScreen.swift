import GIMClientKit
import GIMFeatures
import SwiftUI

/// A chat with its composer and the full message menu (reply, react, copy, edit, delete with confirmation, retry).
public struct ConversationScreen: View {
    private let client: any GimClientAPI
    private let chatId: String
    private let drafts: ComposerDrafts

    @State private var actions: MessageActionsViewModel

    /// - Parameter drafts: unsent text per chat, shared by all chats of the session.
    public init(client: any GimClientAPI, chatId: String, drafts: ComposerDrafts) {
        self.client = client
        self.chatId = chatId
        self.drafts = drafts
        _actions = State(initialValue: MessageActionsViewModel(client: client, chatId: chatId))
    }

    public var body: some View {
        ChatScreen(
            client: client, chatId: chatId,
            contextMenuProvider: { [actions] message, context in
                MessageContextMenu.menu(for: message, context: context, actions: actions)
            }
        ) { timeline, replyingTo, editing in
            ComposerView(
                client: client, chatId: chatId, drafts: drafts, timeline: timeline, replyingTo: replyingTo,
                editing: editing)
        }
        .confirmationDialog(
            Text("Delete this message for everyone?", tableName: "Chat", bundle: .module),
            isPresented: Binding(
                get: { actions.pendingDelete != nil },
                set: { if !$0 { actions.cancelDelete() } }),
            titleVisibility: .visible,
            presenting: actions.pendingDelete
        ) { message in
            Button(String(localized: "Delete", table: "Common", bundle: .module), role: .destructive) {
                Task { await actions.delete(message) }
            }
            Button(String(localized: "Cancel", table: "Common", bundle: .module), role: .cancel) {}
        }
        .alert(
            Text("Something went wrong", tableName: "Common", bundle: .module),
            isPresented: Binding(
                get: { actions.errorMessage != nil },
                set: { if !$0 { actions.dismissError() } })
        ) {
            Button(String(localized: "OK", table: "Common", bundle: .module), role: .cancel) {}
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

import GIMClientKit
import GIMFeatures
import SwiftUI
import UIKit

/// What a message menu can do on the chat screen besides calling the client.
@MainActor
public struct MessageMenuContext {
    public let timeline: TimelineViewModel
    /// Makes the message the composer's reply target.
    public let reply: (MessageItem) -> Void
    /// Puts the composer into edit mode for the message.
    public let edit: (MessageItem) -> Void
}

/// One chat: the timeline, the chat name with who is typing, group info for groups, and a bottom slot for the
/// composer.
public struct ChatScreen<Composer: View>: View {
    private let client: any GimClientAPI
    private let contextMenuProvider: ((MessageItem, MessageMenuContext) -> UIMenu?)?
    private let composer: (TimelineViewModel, Binding<MessageItem?>, Binding<MessageItem?>) -> Composer

    @State private var viewModel: TimelineViewModel
    /// Set by the timeline's Reply action; the composer shows and clears it.
    @State private var replyingTo: MessageItem?
    /// Set by the menu's Edit action; the composer edits it and clears it.
    @State private var editing: MessageItem?

    /// - Parameters:
    ///   - contextMenuProvider: replaces the timeline's default long-press menu; the context starts a reply or an
    ///     edit.
    ///   - composer: placed in the bottom safe area, given the timeline, the message being replied to and the
    ///     message being edited.
    public init(
        client: any GimClientAPI, chatId: String,
        contextMenuProvider: ((MessageItem, MessageMenuContext) -> UIMenu?)? = nil,
        @ViewBuilder composer: @escaping (TimelineViewModel, Binding<MessageItem?>, Binding<MessageItem?>) -> Composer
    ) {
        self.client = client
        self.contextMenuProvider = contextMenuProvider
        self.composer = composer
        _viewModel = State(initialValue: TimelineViewModel(client: client, chatId: chatId))
    }

    public var body: some View {
        TimelineRepresentable(
            viewModel: viewModel, onReply: { menuContext.reply($0) },
            contextMenuProvider: contextMenuProvider.map { provider in { [menuContext] in provider($0, menuContext) } }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer(viewModel, $replyingTo, $editing)
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(viewModel.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let typing = viewModel.typingText {
                        Text(typing)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if viewModel.isGroup {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        // Closes itself once the user left; the chat then shows its leaving state.
                        GroupInfoScreen(client: client, chatId: viewModel.chatId)
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Group info", tableName: "Chat", bundle: .module))
                    .accessibilityHint(Text("Shows members and settings", tableName: "Chat", bundle: .module))
                }
            }
        }
        // Subscriptions end when the screen is popped and the view model is released, not on disappear, so
        // returning from group info keeps the scroll position.
        .task { viewModel.start() }
        .alert(
            Text("Something went wrong", tableName: "Common", bundle: .module),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } })
        ) {
            Button(String(localized: "OK", table: "Common", bundle: .module), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

extension ChatScreen {
    /// Reply and edit exclude each other.
    private var menuContext: MessageMenuContext {
        let replyingTo = $replyingTo
        let editing = $editing
        return MessageMenuContext(
            timeline: viewModel,
            reply: { message in
                editing.wrappedValue = nil
                replyingTo.wrappedValue = message
            },
            edit: { message in
                replyingTo.wrappedValue = nil
                editing.wrappedValue = message
            })
    }
}

extension ChatScreen where Composer == EmptyView {
    /// The chat without a composer.
    public init(client: any GimClientAPI, chatId: String) {
        self.init(client: client, chatId: chatId) { _, _, _ in EmptyView() }
    }
}

/// Hosts `TimelineViewController` in SwiftUI.
private struct TimelineRepresentable: UIViewControllerRepresentable {
    let viewModel: TimelineViewModel
    let onReply: (MessageItem) -> Void
    let contextMenuProvider: ((MessageItem) -> UIMenu?)?

    func makeUIViewController(context: Context) -> TimelineViewController {
        TimelineViewController(viewModel: viewModel, imageLoader: context.environment.imageFileLoader)
    }

    func updateUIViewController(_ controller: TimelineViewController, context: Context) {
        controller.onReply = onReply
        controller.contextMenuProvider = contextMenuProvider
    }
}

#Preview {
    NavigationStack {
        ChatScreen(client: FakeGimClient.demo(), chatId: FakeGimClient.demoGroupChatId)
    }
}

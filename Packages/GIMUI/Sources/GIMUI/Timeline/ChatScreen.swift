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

/// One chat: the timeline, the chat name with who is typing, group info for groups, the chat menu (pin, mute, archive,
/// block) and a bottom slot for the composer, replaced by an unblock bar while the other user is blocked.
public struct ChatScreen<Composer: View>: View {
    private let client: any GimClientAPI
    private let contextMenuProvider: ((MessageItem, MessageMenuContext) -> UIMenu?)?
    private let composer: (TimelineViewModel, Binding<MessageItem?>, Binding<MessageItem?>) -> Composer

    @State private var viewModel: TimelineViewModel
    @State private var actions: ChatActionsViewModel
    /// Set by the menu's Block item; the confirmation dialog blocks.
    @State private var confirmsBlock = false
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
        _actions = State(initialValue: ChatActionsViewModel(client: client, chatId: chatId))
    }

    public var body: some View {
        TimelineRepresentable(
            viewModel: viewModel, onReply: { menuContext.reply($0) },
            contextMenuProvider: contextMenuProvider.map { provider in { [menuContext] in provider($0, menuContext) } }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if actions.isBlocked {
                BlockedChatBar { Task { await actions.unblock() } }
            } else {
                composer(viewModel, $replyingTo, $editing)
            }
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    chatMenu
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("More", tableName: "Chat", bundle: .module))
                .accessibilityIdentifier("chat.menu")
            }
        }
        // Subscriptions end when the screen is popped and the view model is released, not on disappear, so
        // returning from group info keeps the scroll position.
        .task {
            viewModel.start()
            actions.start()
        }
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
        .confirmationDialog(
            Text("Block \(actions.peerName ?? viewModel.title)?", tableName: "Chat", bundle: .module),
            isPresented: $confirmsBlock, titleVisibility: .visible
        ) {
            Button(String(localized: "Block", table: "Chat", bundle: .module), role: .destructive) {
                Task { await actions.block() }
            }
            Button(String(localized: "Cancel", table: "Common", bundle: .module), role: .cancel) {}
        } message: {
            Text(
                "You won't get their messages, and they can't add you to new chats.", tableName: "Chat", bundle: .module
            )
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

extension ChatScreen {
    /// Archiving keeps the chat open.
    @ViewBuilder
    private var chatMenu: some View {
        Button {
            Task { await actions.setPinned(!actions.isPinned) }
        } label: {
            if actions.isPinned {
                Label(String(localized: "Unpin", table: "Chat", bundle: .module), systemImage: "pin.slash")
            } else {
                Label(String(localized: "Pin", table: "Chat", bundle: .module), systemImage: "pin")
            }
        }
        .accessibilityIdentifier("chat.menu.pin")
        if actions.isMuted {
            Button {
                Task { await actions.unmute() }
            } label: {
                Label(String(localized: "Unmute", table: "Chat", bundle: .module), systemImage: "bell")
            }
            .accessibilityIdentifier("chat.menu.unmute")
        } else {
            Menu {
                ForEach(ChatMuteOption.allCases, id: \.self) { option in
                    Button(option.title) {
                        Task { await actions.mute(option) }
                    }
                    .accessibilityIdentifier("chat.menu.mute.\(String(describing: option))")
                }
            } label: {
                Label(String(localized: "Mute", table: "Chat", bundle: .module), systemImage: "bell.slash")
            }
            .accessibilityIdentifier("chat.menu.mute")
        }
        Button {
            Task { await actions.setArchived(!actions.isArchived) }
        } label: {
            if actions.isArchived {
                Label(String(localized: "Unarchive", table: "Chat", bundle: .module), systemImage: "tray.and.arrow.up")
            } else {
                Label(String(localized: "Archive", table: "Chat", bundle: .module), systemImage: "archivebox")
            }
        }
        .accessibilityIdentifier("chat.menu.archive")
        if actions.canBlock {
            if actions.isBlocked {
                Button {
                    Task { await actions.unblock() }
                } label: {
                    Label(
                        String(localized: "Unblock", table: "Chat", bundle: .module), systemImage: "hand.raised.slash")
                }
                .accessibilityIdentifier("chat.menu.unblock")
            } else {
                Button(role: .destructive) {
                    confirmsBlock = true
                } label: {
                    Label(String(localized: "Block", table: "Chat", bundle: .module), systemImage: "hand.raised")
                }
                .accessibilityIdentifier("chat.menu.block")
            }
        }
    }

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

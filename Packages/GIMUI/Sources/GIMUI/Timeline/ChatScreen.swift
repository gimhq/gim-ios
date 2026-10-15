import GIMClientKit
import GIMFeatures
import SwiftUI
import UIKit

/// One chat: the timeline, the chat name with who is typing, group info for groups, and a bottom slot for the
/// composer.
public struct ChatScreen<Composer: View>: View {
    private let client: any GimClientAPI
    private let contextMenuProvider: ((MessageItem) -> UIMenu?)?
    private let composer: (TimelineViewModel, Binding<MessageItem?>) -> Composer

    @State private var viewModel: TimelineViewModel
    /// Set by the timeline's Reply action; the composer shows and clears it.
    @State private var replyingTo: MessageItem?
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - contextMenuProvider: replaces the timeline's default long-press menu.
    ///   - composer: placed in the bottom safe area, given the timeline and the message being replied to.
    public init(
        client: any GimClientAPI, chatId: String, contextMenuProvider: ((MessageItem) -> UIMenu?)? = nil,
        @ViewBuilder composer: @escaping (TimelineViewModel, Binding<MessageItem?>) -> Composer
    ) {
        self.client = client
        self.contextMenuProvider = contextMenuProvider
        self.composer = composer
        _viewModel = State(initialValue: TimelineViewModel(client: client, chatId: chatId))
    }

    public var body: some View {
        TimelineRepresentable(
            viewModel: viewModel, onReply: { replyingTo = $0 }, contextMenuProvider: contextMenuProvider
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer(viewModel, $replyingTo)
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
                        GroupInfoScreen(client: client, chatId: viewModel.chatId, onLeft: { dismiss() })
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Group Info")
                }
            }
        }
        // Subscriptions end when the screen is popped and the view model is released, not on disappear, so
        // returning from group info keeps the scroll position.
        .task { viewModel.start() }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

extension ChatScreen where Composer == EmptyView {
    /// The chat without a composer.
    public init(client: any GimClientAPI, chatId: String) {
        self.init(client: client, chatId: chatId) { _, _ in EmptyView() }
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

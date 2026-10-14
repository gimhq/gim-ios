import GIMClientKit
import GIMFeatures
import SwiftUI

/// The signed-in home screen: every chat, newest activity first, served by gim-core from its local database.
public struct ChatListScreen: View {
    private let client: any GimClientAPI
    private let onOpen: (String) -> Void
    private let onOpenSettings: (() -> Void)?

    @State private var viewModel: ChatListViewModel
    @State private var showsNewChat = false

    /// - Parameter onOpenSettings: shows a settings button in the toolbar when set.
    public init(client: any GimClientAPI, onOpen: @escaping (String) -> Void, onOpenSettings: (() -> Void)? = nil) {
        self.client = client
        self.onOpen = onOpen
        self.onOpenSettings = onOpenSettings
        _viewModel = State(initialValue: ChatListViewModel(client: client))
    }

    public var body: some View {
        List(viewModel.rows) { row in
            Button {
                onOpen(row.id)
            } label: {
                ChatRowView(row: row)
            }
        }
        .listStyle(.plain)
        .overlay { emptyState }
        .safeAreaInset(edge: .top, spacing: 0) {
            ConnectionBanner(state: viewModel.connectionState)
                .animation(.default, value: viewModel.connectionState)
        }
        .refreshable { viewModel.refresh() }
        .navigationTitle("Chats")
        .toolbar {
            if let onOpenSettings {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onOpenSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewChat = true
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showsNewChat) {
            NavigationStack {
                NewChatScreen(client: client) { chatId in
                    showsNewChat = false
                    onOpen(chatId)
                }
            }
        }
        .task { viewModel.start() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = viewModel.errorMessage, viewModel.rows.isEmpty {
            ContentUnavailableView {
                Label("Can't Load Chats", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { viewModel.refresh() }
            }
        } else if viewModel.isLoading {
            ProgressView()
        } else if viewModel.rows.isEmpty {
            ContentUnavailableView {
                Label("No Chats Yet", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Start a conversation by searching for someone's handle.")
            } actions: {
                Button("New Chat") { showsNewChat = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct ChatRowView: View {
    let row: ChatRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(id: row.id, name: row.title, avatarPath: nil, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let time = row.time {
                        Text(time)
                            .font(.caption)
                            .foregroundStyle(row.unreadCount > 0 ? Color.accentColor : Color.secondary)
                    }
                }
                HStack(alignment: .top) {
                    Text(row.preview ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    UnreadBadge(count: row.unreadCount)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        ChatListScreen(client: FakeGimClient.demo(), onOpen: { _ in }, onOpenSettings: {})
    }
}

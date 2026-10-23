import GIMClientKit
import GIMFeatures
import SwiftUI

/// The signed-in home screen: every chat, newest activity first, served by gim-core from its local database.
public struct ChatListScreen: View {
    private let client: any GimClientAPI
    private let session: Session?
    private let onOpen: (String) -> Void
    private let onOpenSettings: (() -> Void)?

    @State private var viewModel: ChatListViewModel
    @State private var showsNewChat = false

    /// - Parameters:
    ///   - onOpenSettings: shows a settings button in the toolbar when set.
    public init(
        client: any GimClientAPI, session: Session? = nil, onOpen: @escaping (String) -> Void,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.client = client
        self.session = session
        self.onOpen = onOpen
        self.onOpenSettings = onOpenSettings
        _viewModel = State(initialValue: ChatListViewModel(client: client))
    }

    public var body: some View {
        List(viewModel.rows) { row in
            Button {
                onOpen(row.id)
            } label: {
                ChatRowView(row: row, subtitle: viewModel.subtitle(for: row))
            }
            .accessibilityIdentifier("chatList.row")
        }
        .listStyle(.plain)
        .overlay { emptyState }
        .safeAreaInset(edge: .top, spacing: 0) {
            ConnectionBanner(state: viewModel.connectionState)
                .animation(.default, value: viewModel.connectionState)
        }
        .refreshable { viewModel.refresh() }
        .navigationTitle(Text("Chats", tableName: "Chat", bundle: .module))
        .toolbar {
            if let onOpenSettings {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onOpenSettings) {
                        if let session {
                            AvatarView(id: session.userId, name: session.displayName, avatarPath: nil, size: 30)
                        } else {
                            Label(
                                String(localized: "Settings", table: "Chat", bundle: .module), systemImage: "gearshape")
                        }
                    }
                    .accessibilityLabel(String(localized: "Settings", table: "Chat", bundle: .module))
                    .accessibilityIdentifier("chatList.settings")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewChat = true
                } label: {
                    Label(
                        String(localized: "New chat", table: "Chat", bundle: .module), systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("chatList.newChat")
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
                Label(
                    String(localized: "Couldn't load chats", table: "Chat", bundle: .module),
                    systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button(String(localized: "Try again", table: "Common", bundle: .module)) { viewModel.refresh() }
            }
        } else if viewModel.isLoading {
            ProgressView()
        } else if viewModel.rows.isEmpty {
            ContentUnavailableView {
                Label(
                    String(localized: "No chats yet", table: "Chat", bundle: .module),
                    systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Start a chat. Search for a friend's username.", tableName: "Chat", bundle: .module)
            } actions: {
                Button(String(localized: "New chat", table: "Chat", bundle: .module)) { showsNewChat = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct ChatRowView: View {
    let row: ChatRow
    let subtitle: String

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
                    Text(subtitle)
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

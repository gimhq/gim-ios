import GIMClientKit
import GIMFeatures
import SwiftUI

/// The signed-in home screen: every chat that is not archived, pinned first, then newest activity first, served by
/// gim-core from its local database. Archived chats sit behind a row at the end.
public struct ChatListScreen: View {
    private let client: any GimClientAPI
    private let session: Session?
    private let onOpen: (String) -> Void
    private let onOpenSettings: (() -> Void)?

    @State private var viewModel: ChatListViewModel
    @State private var showsNewChat = false
    @State private var showsArchived = false

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
        List {
            ForEach(viewModel.rows) { row in
                ChatListRow(row: row, viewModel: viewModel, onOpen: onOpen)
            }
            if viewModel.hasArchived {
                archivedRow
            }
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
        .chatActionErrorAlert(viewModel, isActive: !showsArchived)
        .sheet(isPresented: $showsArchived) {
            NavigationStack {
                ArchivedChatsScreen(viewModel: viewModel) { chatId in
                    showsArchived = false
                    onOpen(chatId)
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

    private var archivedRow: some View {
        Button {
            showsArchived = true
        } label: {
            HStack {
                Label(String(localized: "Archived chats", table: "Chat", bundle: .module), systemImage: "archivebox")
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(viewModel.archivedRows.count, format: .number)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chatList.archived")
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
        } else if viewModel.rows.isEmpty, !viewModel.hasArchived {
            ContentUnavailableView {
                Label(
                    String(localized: "No chats yet", table: "Chat", bundle: .module),
                    systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text(
                    "Start a chat. Scan a friend's QR code or paste their Account ID.", tableName: "Chat",
                    bundle: .module)
            } actions: {
                Button(String(localized: "Start a chat", table: "Chat", bundle: .module)) { showsNewChat = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("chatList.emptyNewChat")
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChatListScreen(client: FakeGimClient.demo(), onOpen: { _ in }, onOpenSettings: {})
    }
}

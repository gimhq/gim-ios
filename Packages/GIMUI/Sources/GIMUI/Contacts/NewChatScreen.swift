import GIMClientKit
import GIMFeatures
import SwiftUI

/// Finds someone by exact handle and opens a direct chat; links to group creation. Shown inside a navigation stack.
public struct NewChatScreen: View {
    private let client: any GimClientAPI
    private let onOpen: (String) -> Void

    @State private var viewModel: NewChatViewModel
    @Environment(\.dismiss) private var dismiss

    /// - Parameter onOpen: called with the direct or group chat that was created.
    public init(client: any GimClientAPI, onOpen: @escaping (String) -> Void) {
        self.client = client
        self.onOpen = onOpen
        _viewModel = State(initialValue: NewChatViewModel(client: client))
    }

    public var body: some View {
        List {
            Section {
                NavigationLink {
                    NewGroupScreen(client: client, onCreated: onOpen)
                } label: {
                    Label("New Group", systemImage: "person.3")
                }
                .accessibilityIdentifier("newChat.newGroup")
            }
            Section {
                result
            } footer: {
                if let error = viewModel.startError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .searchable(
            text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Handle"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("New Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch viewModel.state {
        case .idle:
            Text("Enter the exact handle of the person you want to message.")
                .foregroundStyle(.secondary)
        case .searching:
            HStack {
                ProgressView()
                Text("Searching…").foregroundStyle(.secondary)
            }
        case .found(let user):
            Button {
                Task {
                    if let chatId = await viewModel.startChat() { onOpen(chatId) }
                }
            } label: {
                HStack(spacing: 12) {
                    UserRow(user: user)
                    Spacer()
                    if viewModel.isStarting { ProgressView() }
                }
            }
            .disabled(viewModel.isStarting)
        case .notFound:
            Label("No one uses this handle.", systemImage: "person.crop.circle.badge.questionmark")
                .foregroundStyle(.secondary)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

/// Avatar, name and handle of one user. A user without a handle (remote users may have none) shows the short user
/// id instead.
struct UserRow: View {
    let user: UserProfile
    var detail: String?

    var body: some View {
        let name = UserLabel.name(for: user)
        HStack(spacing: 12) {
            AvatarView(id: user.userId, name: name, avatarPath: nil, size: 40)
            VStack(alignment: .leading) {
                Text(name).foregroundStyle(.primary)
                Text(detail ?? UserLabel.detail(for: user))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        NewChatScreen(client: FakeGimClient.demo()) { _ in }
    }
}

import GIMClientKit
import GIMFeatures
import SwiftUI

/// The blocked people, each with an unblock button.
struct BlockedUsersScreen: View {
    @State private var viewModel: BlockedUsersViewModel

    init(client: any GimClientAPI) {
        _viewModel = State(initialValue: BlockedUsersViewModel(client: client))
    }

    var body: some View {
        List {
            if !viewModel.rows.isEmpty {
                Section {
                    ForEach(viewModel.rows) { row in
                        rowView(row)
                    }
                } footer: {
                    footer
                }
            } else if viewModel.errorMessage != nil {
                Section {
                } footer: {
                    footer
                }
            }
        }
        .overlay {
            if viewModel.isLoaded, viewModel.rows.isEmpty, viewModel.errorMessage == nil {
                ContentUnavailableView {
                    Label {
                        Text("No one is blocked.", tableName: "Settings", bundle: .module)
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                } description: {
                    Text(
                        "You won't get messages from people you block, and they can't add you to groups.",
                        tableName: "Settings", bundle: .module)
                }
            }
        }
        .navigationTitle(Text("Blocked people", tableName: "Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private func rowView(_ row: BlockedUsersViewModel.Row) -> some View {
        HStack(spacing: 12) {
            AvatarView(id: row.userId, name: row.name ?? row.userId, avatarPath: nil)
            VStack(alignment: .leading) {
                if let name = row.name {
                    Text(name)
                    if let detail = row.detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text(row.userId)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button {
                Task { await viewModel.unblock(userId: row.userId) }
            } label: {
                Text("Unblock", tableName: "Settings", bundle: .module)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.unblocking.contains(row.userId))
            .accessibilityIdentifier("settings.blocked.unblock")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let error = viewModel.errorMessage {
            Text(error).foregroundStyle(.red)
        } else {
            Text(
                "You won't get messages from people you block, and they can't add you to groups.",
                tableName: "Settings", bundle: .module)
        }
    }
}

import GIMClientKit
import GIMFeatures
import SwiftUI

/// Group name plus members added by handle. Shown inside a navigation stack.
public struct NewGroupScreen: View {
    private let onCreated: (String) -> Void

    @State private var viewModel: NewGroupViewModel

    public init(client: any GimClientAPI, onCreated: @escaping (String) -> Void) {
        self.onCreated = onCreated
        _viewModel = State(initialValue: NewGroupViewModel(client: client))
    }

    public var body: some View {
        Form {
            Section(String(localized: "Name", table: "Contacts", bundle: .module)) {
                TextField(String(localized: "Group name", table: "Contacts", bundle: .module), text: $viewModel.name)
                    .submitLabel(.next)
                    .accessibilityIdentifier("newGroup.name")
            }

            Section {
                if !viewModel.members.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(viewModel.members, id: \.userId) { member in
                                MemberChip(user: member) { viewModel.removeMember(member.userId) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                HStack {
                    TextField(
                        String(localized: "Add by username", table: "Contacts", bundle: .module),
                        text: $viewModel.memberHandle
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addMember)
                    .accessibilityIdentifier("newGroup.memberHandle")
                    if viewModel.isAddingMember {
                        ProgressView()
                    } else {
                        Button(String(localized: "Add", table: "Common", bundle: .module), action: addMember)
                            .disabled(viewModel.memberHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("newGroup.addMember")
                    }
                }
            } header: {
                Text("Members", tableName: "Contacts", bundle: .module)
            } footer: {
                if let error = viewModel.memberError {
                    Text(error).foregroundStyle(.red)
                } else if let message = viewModel.validationMessage {
                    Text(message)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .disabled(viewModel.isCreating)
        .navigationTitle(Text("New group", tableName: "Contacts", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isCreating {
                    ProgressView()
                } else {
                    Button(String(localized: "Create", table: "Contacts", bundle: .module)) {
                        Task {
                            if let chatId = await viewModel.create() { onCreated(chatId) }
                        }
                    }
                    .disabled(!viewModel.canCreate)
                    .accessibilityIdentifier("newGroup.create")
                }
            }
        }
    }

    private func addMember() {
        Task { await viewModel.addMember() }
    }
}

private struct MemberChip: View {
    let user: UserProfile
    let remove: () -> Void

    var body: some View {
        let name = UserLabel.name(for: user)
        HStack(spacing: 6) {
            AvatarView(id: user.userId, name: name, avatarPath: nil, size: 24)
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove \(name)", tableName: "Contacts", bundle: .module))
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
    }
}

#Preview {
    NavigationStack {
        NewGroupScreen(client: FakeGimClient.demo()) { _ in }
    }
}

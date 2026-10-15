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
            Section("Name") {
                TextField("Group name", text: $viewModel.name)
                    .submitLabel(.next)
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
                    TextField("Add by handle", text: $viewModel.memberHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addMember)
                    if viewModel.isAddingMember {
                        ProgressView()
                    } else {
                        Button("Add", action: addMember)
                            .disabled(viewModel.memberHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Members")
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
        .navigationTitle("New Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isCreating {
                    ProgressView()
                } else {
                    Button("Create") {
                        Task {
                            if let chatId = await viewModel.create() { onCreated(chatId) }
                        }
                    }
                    .disabled(!viewModel.canCreate)
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
        HStack(spacing: 6) {
            AvatarView(id: user.userId, name: user.displayName, avatarPath: nil, size: 24)
            Text(user.displayName)
                .font(.subheadline)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(user.displayName)")
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

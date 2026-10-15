import GIMClientKit
import GIMFeatures
import SwiftUI

/// Chat details and, for groups, member management. Pushed from the chat screen.
public struct GroupInfoScreen: View {
    @State private var viewModel: GroupInfoViewModel

    public init(client: any GimClientAPI, chatId: ChatId) {
        _viewModel = State(initialValue: GroupInfoViewModel(client: client, chatId: chatId))
    }

    public var body: some View {
        Form {
            if let details = viewModel.details {
                header(details.summary)
                membersSection(details)
                if viewModel.canEditMembers { addMemberSection }
            } else if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    if viewModel.details == nil {
                        Button("Try Again") { Task { await viewModel.load() } }
                    }
                }
            }
        }
        .navigationTitle(viewModel.details?.summary.kind == .direct ? "Chat Info" : "Group Info")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .confirmationDialog(
            "Remove \(viewModel.pendingRemoval?.user.displayName ?? "member") from the group?",
            isPresented: Binding(
                get: { viewModel.pendingRemoval != nil },
                set: { if !$0 { viewModel.cancelRemoval() } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await viewModel.confirmRemoval() }
            }
        }
    }

    private func header(_ summary: ChatSummary) -> some View {
        Section {
            VStack(spacing: 8) {
                AvatarView(id: summary.id, name: summary.title, avatarPath: summary.avatarPath, size: 80)
                Text(summary.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if summary.kind == .group {
                    Text(summary.memberCount == 1 ? "1 member" : "\(summary.memberCount) members")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private func membersSection(_ details: ChatDetails) -> some View {
        Section("Members") {
            ForEach(details.members, id: \.user.userId) { member in
                HStack {
                    UserRow(user: member.user)
                    Spacer()
                    if member.isSelf {
                        Text("You").foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    if viewModel.canEditMembers && !member.isSelf {
                        Button("Remove", role: .destructive) { viewModel.requestRemoval(member) }
                    }
                }
            }
        }
    }

    private var addMemberSection: some View {
        Section("Add Member") {
            HStack {
                TextField("Handle", text: $viewModel.memberHandle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addMember)
                if viewModel.isUpdatingMembers {
                    ProgressView()
                } else {
                    Button("Add", action: addMember)
                        .disabled(viewModel.memberHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addMember() {
        Task { await viewModel.addMember() }
    }
}

#Preview {
    NavigationStack {
        GroupInfoScreen(client: FakeGimClient.demo(), chatId: FakeGimClient.demoGroupChatId)
    }
}

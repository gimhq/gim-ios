import GIMClientKit
import GIMFeatures
import SwiftUI

/// Chat details and, for groups, the name, member management and leaving. Pushed from the chat screen.
public struct GroupInfoScreen: View {
    private let onLeft: () -> Void

    @State private var viewModel: GroupInfoViewModel
    @State private var confirmsLeave = false

    /// - Parameter onLeft: called after the user left the group.
    public init(client: any GimClientAPI, chatId: String, onLeft: @escaping () -> Void = {}) {
        self.onLeft = onLeft
        _viewModel = State(initialValue: GroupInfoViewModel(client: client, chatId: chatId))
    }

    public var body: some View {
        Form {
            if let summary = viewModel.summary {
                header(summary)
                if viewModel.isGroup { nameSection }
                membersSection(summary)
                if viewModel.canEditMembers { addMemberSection }
                if viewModel.isGroup { leaveSection }
            } else if viewModel.errorMessage == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    if viewModel.members == nil {
                        Button("Try Again") { Task { await viewModel.load() } }
                    }
                }
            }
        }
        .navigationTitle(viewModel.summary?.kind == .direct ? "Chat Info" : "Group Info")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.start()
            await viewModel.load()
        }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.hasLeft) { _, hasLeft in
            if hasLeft { onLeft() }
        }
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
        .confirmationDialog("Leave this group?", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive) {
                Task { await viewModel.leave() }
            }
        }
    }

    private func header(_ summary: ChatSummary) -> some View {
        Section {
            VStack(spacing: 8) {
                AvatarView(id: summary.chatId, name: summary.name, avatarPath: nil, size: 80)
                Text(summary.name)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if summary.kind == .group {
                    Text(Self.memberCountText(summary.memberCount))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private var nameSection: some View {
        Section("Name") {
            HStack {
                TextField("Group name", text: $viewModel.editedName)
                    .submitLabel(.done)
                    .onSubmit(saveName)
                if viewModel.isSavingName {
                    ProgressView()
                } else {
                    Button("Save", action: saveName)
                        .disabled(viewModel.nameToSave == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func membersSection(_ summary: ChatSummary) -> some View {
        if let members = viewModel.members {
            Section("Members") {
                ForEach(members) { member in
                    HStack {
                        UserRow(user: member.user)
                        Spacer()
                        if member.isSelf {
                            Text("You").foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if viewModel.canRemoveMembers && !member.isSelf {
                            Button("Remove", role: .destructive) { viewModel.requestRemoval(member) }
                        }
                    }
                }
            }
        } else if viewModel.membersUnavailable {
            Section {
                Text(Self.memberCountText(summary.memberCount))
            } header: {
                Text("Members")
            } footer: {
                Text("The member list couldn't be loaded.")
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

    private var leaveSection: some View {
        Section {
            Button("Leave Group", role: .destructive) { confirmsLeave = true }
                .disabled(viewModel.isLeaving)
        }
    }

    private func addMember() {
        Task { await viewModel.addMember() }
    }

    private func saveName() {
        Task { await viewModel.saveName() }
    }

    private static func memberCountText(_ count: UInt32) -> String {
        count == 1 ? "1 member" : "\(count) members"
    }
}

#Preview {
    NavigationStack {
        GroupInfoScreen(client: FakeGimClient.demo(), chatId: FakeGimClient.demoGroupChatId)
    }
}

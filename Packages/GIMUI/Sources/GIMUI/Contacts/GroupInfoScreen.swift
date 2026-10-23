import GIMClientKit
import GIMFeatures
import SwiftUI

/// Chat details and, for groups, the name, member management and leaving. Pushed from the chat screen.
public struct GroupInfoScreen: View {
    @State private var viewModel: GroupInfoViewModel
    @State private var confirmsLeave = false
    @Environment(\.dismiss) private var dismiss

    /// The screen closes once the user left the group.
    public init(client: any GimClientAPI, chatId: String) {
        _viewModel = State(initialValue: GroupInfoViewModel(client: client, chatId: chatId))
    }

    public var body: some View {
        Form {
            if let summary = viewModel.summary {
                header(summary)
                if viewModel.isGroup && viewModel.isActive { nameSection }
                membersSection(summary)
                if viewModel.canEditMembers { addMemberSection }
                if viewModel.canLeave { leaveSection }
            } else if viewModel.errorMessage == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    if viewModel.members == nil {
                        Button(String(localized: "Try again", table: "Common", bundle: .module)) {
                            Task { await viewModel.load() }
                        }
                    }
                }
            }
        }
        .navigationTitle(
            viewModel.summary?.kind == .direct
                ? Text("Chat info", tableName: "Contacts", bundle: .module)
                : Text("Group info", tableName: "Contacts", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.start()
            await viewModel.load()
        }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.hasLeft) { _, hasLeft in
            if hasLeft { dismiss() }
        }
        .confirmationDialog(
            Text("Remove \(pendingRemovalName) from the group?", tableName: "Contacts", bundle: .module),
            isPresented: Binding(
                get: { viewModel.pendingRemoval != nil },
                set: { if !$0 { viewModel.cancelRemoval() } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Remove", table: "Common", bundle: .module), role: .destructive) {
                Task { await viewModel.confirmRemoval() }
            }
        }
        .confirmationDialog(
            Text("Leave this group?", tableName: "Contacts", bundle: .module), isPresented: $confirmsLeave,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Leave group", table: "Contacts", bundle: .module), role: .destructive) {
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
                    Self.memberCountText(summary.memberCount)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private var nameSection: some View {
        Section(String(localized: "Name", table: "Contacts", bundle: .module)) {
            HStack {
                TextField(
                    String(localized: "Group name", table: "Contacts", bundle: .module), text: $viewModel.editedName
                )
                    .submitLabel(.done)
                    .onSubmit(saveName)
                if viewModel.isSavingName {
                    ProgressView()
                } else {
                    Button(String(localized: "Save", table: "Common", bundle: .module), action: saveName)
                        .disabled(viewModel.nameToSave == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func membersSection(_ summary: ChatSummary) -> some View {
        if let members = viewModel.members {
            Section(String(localized: "Members", table: "Contacts", bundle: .module)) {
                ForEach(members) { member in
                    HStack {
                        UserRow(user: member.user)
                        Spacer()
                        if member.isSelf {
                            Text("You", tableName: "Contacts", bundle: .module).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if viewModel.canRemoveMembers && !member.isSelf {
                            Button(String(localized: "Remove", table: "Common", bundle: .module), role: .destructive) {
                                viewModel.requestRemoval(member)
                            }
                        }
                    }
                }
            }
        } else if viewModel.membersUnavailable {
            Section {
                Self.memberCountText(summary.memberCount)
            } header: {
                Text("Members", tableName: "Contacts", bundle: .module)
            } footer: {
                Text("Couldn't load the members. Try again.", tableName: "Contacts", bundle: .module)
            }
        }
    }

    private var addMemberSection: some View {
        Section(String(localized: "Add member", table: "Contacts", bundle: .module)) {
            HStack {
                TextField(
                    String(localized: "Username", table: "Contacts", bundle: .module), text: $viewModel.memberHandle
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addMember)
                if viewModel.isUpdatingMembers {
                    ProgressView()
                } else {
                    Button(String(localized: "Add", table: "Common", bundle: .module), action: addMember)
                        .disabled(viewModel.memberHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var leaveSection: some View {
        Section {
            Button(String(localized: "Leave group", table: "Contacts", bundle: .module), role: .destructive) {
                confirmsLeave = true
            }
                .disabled(viewModel.isLeaving)
                .accessibilityIdentifier("groupInfo.leave")
        }
    }

    private func addMember() {
        Task { await viewModel.addMember() }
    }

    private func saveName() {
        Task { await viewModel.saveName() }
    }

    private var pendingRemovalName: String {
        viewModel.pendingRemoval.map { UserLabel.name(for: $0.user) }
            ?? String(localized: "this member", table: "Contacts", bundle: .module)
    }

    private static func memberCountText(_ count: UInt32) -> Text {
        count == 1
            ? Text("1 member", tableName: "Contacts", bundle: .module)
            : Text("\(Int(count)) members", tableName: "Contacts", bundle: .module)
    }
}

#Preview {
    NavigationStack {
        GroupInfoScreen(client: FakeGimClient.demo(), chatId: FakeGimClient.demoGroupChatId)
    }
}

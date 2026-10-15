import Foundation
import GIMClientKit
import Observation

/// Shows a chat's details and manages a group: members, name and leaving.
///
/// gim-core has no members listener, so the member list is queried with `chatMembers` and queried again when the
/// chat list updates this chat or a membership change arrives in its timeline. When the gim-core build does not
/// implement `chatMembers` yet (`GimError.NotImplemented`), only the member count from the chat summary is shown.
@MainActor
@Observable
public final class GroupInfoViewModel {
    public struct Member: Sendable, Hashable, Identifiable {
        public let user: UserProfile
        public let isSelf: Bool

        public init(user: UserProfile, isSelf: Bool) {
            self.user = user
            self.isSelf = isSelf
        }

        public var id: String { user.userId }
    }

    public let chatId: String
    /// The chat's chat list entry; `nil` until the chat list arrives or once the chat is gone.
    public private(set) var summary: ChatSummary?
    /// `nil` until loaded, and while `membersUnavailable`.
    public private(set) var members: [Member]?
    /// `chatMembers` is not implemented by this gim-core build: show `summary.memberCount` without a list.
    public private(set) var membersUnavailable = false
    public private(set) var isLoading = false
    /// Error from the last load or change.
    public private(set) var errorMessage: String?

    /// Handle typed into the "add member" field.
    public var memberHandle = ""
    public private(set) var isUpdatingMembers = false
    /// Member waiting for the user to confirm removal.
    public private(set) var pendingRemoval: Member?

    /// Group name field; filled from the summary when it first arrives.
    public var editedName = ""
    public private(set) var isSavingName = false
    public private(set) var isLeaving = false
    /// Set once the user left the group; the screen should close.
    public private(set) var hasLeft = false

    private let client: any GimClientAPI
    @ObservationIgnored private var chatList: [ChatSummary] = []
    @ObservationIgnored private var selfUserId: String?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var appliedGeneration = 0
    @ObservationIgnored private var activeLoads = 0
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var timelineTask: Task<Void, Never>?

    public init(client: any GimClientAPI, chatId: String) {
        self.client = client
        self.chatId = chatId
    }

    deinit {
        listTask?.cancel()
        timelineTask?.cancel()
    }

    public var isGroup: Bool { summary?.kind == .group }
    /// Members can only be added in groups.
    public var canEditMembers: Bool { isGroup }
    /// Removal needs the member list.
    public var canRemoveMembers: Bool { isGroup && !membersUnavailable }

    /// Follows the chat list (for the summary) and the timeline (for membership changes). Call `load()` for the
    /// first member query.
    public func start() {
        guard listTask == nil else { return }
        let client = client
        let chatId = chatId
        listTask = Task { [weak self] in
            do {
                for await diffs in try await ListenerBridge.chatList(client) {
                    self?.applyChatList(diffs)
                }
            } catch {
                self?.fail(error)
            }
        }
        timelineTask = Task { [weak self] in
            guard let stream = try? await ListenerBridge.timeline(client, chatId: chatId) else { return }
            var isInitialReset = true
            for await diffs in stream {
                if !isInitialReset && Self.containsMembershipChange(diffs) { await self?.load() }
                isInitialReset = false
            }
        }
    }

    public func stop() {
        listTask?.cancel()
        timelineTask?.cancel()
        listTask = nil
        timelineTask = nil
    }

    /// Queries the members. Queries may overlap (listener-driven re-queries run alongside the one after a change);
    /// each result is applied unless a query started later has already been applied, so a slow older query never
    /// overwrites a newer list and a finished query is not held back by one still running.
    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        activeLoads += 1
        isLoading = true
        defer {
            activeLoads -= 1
            isLoading = activeLoads > 0
        }
        do {
            if selfUserId == nil { selfUserId = try await client.session()?.userId }
            let users = try await client.chatMembers(chatId: chatId)
            guard claimResult(generation) else { return }
            members = users.map { Member(user: $0, isSelf: $0.userId == selfUserId) }
            membersUnavailable = false
            errorMessage = nil
        } catch GimError.NotImplemented {
            guard claimResult(generation) else { return }
            members = nil
            membersUnavailable = true
            pendingRemoval = nil
        } catch {
            guard claimResult(generation) else { return }
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Whether the result of query `generation` may be applied; records it as the newest applied one.
    private func claimResult(_ generation: Int) -> Bool {
        // Leaving removes the chat; queries still in flight would only report it missing.
        guard generation > appliedGeneration, !isLeaving, !hasLeft else { return false }
        appliedGeneration = generation
        return true
    }

    /// Looks up `memberHandle` and adds the user.
    public func addMember() async {
        let handle = OnboardingValidation.normalizedHandle(memberHandle)
        guard !handle.isEmpty else { return }
        await updateMembers {
            guard let user = try await self.client.findUser(handle: handle) else {
                self.errorMessage = "No one uses the handle @\(handle)."
                return false
            }
            try await self.client.addMembers(chatId: self.chatId, userIds: [user.userId])
            self.memberHandle = ""
            return true
        }
    }

    /// Asks for confirmation before removing `member`. The current user leaves instead.
    public func requestRemoval(_ member: Member) {
        guard canRemoveMembers, !member.isSelf else { return }
        pendingRemoval = member
    }

    public func cancelRemoval() {
        pendingRemoval = nil
    }

    /// Removes the member awaiting confirmation.
    public func confirmRemoval() async {
        guard let member = pendingRemoval else { return }
        pendingRemoval = nil
        await updateMembers {
            try await self.client.removeMember(chatId: self.chatId, userId: member.user.userId)
            return true
        }
    }

    /// The trimmed `editedName` when it differs from the current name.
    public var nameToSave: String? {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isGroup, !name.isEmpty, name != summary?.name else { return nil }
        return name
    }

    /// Renames the group; the chat list then delivers the new summary.
    public func saveName() async {
        guard let name = nameToSave, !isSavingName else { return }
        isSavingName = true
        errorMessage = nil
        defer { isSavingName = false }
        do {
            try await client.setGroupInfo(chatId: chatId, name: name, avatarFilePath: nil)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    public func leave() async {
        guard isGroup, !isLeaving else { return }
        isLeaving = true
        errorMessage = nil
        defer { isLeaving = false }
        do {
            try await client.leaveChat(chatId: chatId)
            stop()
            hasLeft = true
            errorMessage = nil
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Runs `change` and queries the members when it reports a change.
    private func updateMembers(_ change: () async throws -> Bool) async {
        guard !isUpdatingMembers else { return }
        isUpdatingMembers = true
        errorMessage = nil
        defer { isUpdatingMembers = false }
        do {
            guard try await change() else { return }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
            return
        }
        await load()
    }

    private func applyChatList(_ diffs: [ChatListDiff]) {
        do {
            try DiffApplier.apply(diffs, to: &chatList)
        } catch {
            // Out of sync with the core; a new subscription starts with a reset.
            stop()
            start()
            return
        }
        let previous = summary
        summary = chatList.first { $0.chatId == chatId }
        if previous == nil, let summary, editedName.isEmpty { editedName = summary.name }
        if let previous, let summary, previous != summary { Task { await load() } }
    }

    private func fail(_ error: any Error) {
        errorMessage = ErrorPresenter.message(for: error)
    }

    nonisolated static func containsMembershipChange(_ diffs: [TimelineDiff]) -> Bool {
        diffs.contains { diff in
            let items: [TimelineItem]
            switch diff.vectorDiff {
            case .append(let values), .reset(let values): items = values
            case .pushFront(let value), .pushBack(let value), .insert(_, let value), .set(_, let value): items = [value]
            case .clear, .popFront, .popBack, .remove, .truncate: items = []
            }
            return items.contains { if case .membershipChange = $0 { true } else { false } }
        }
    }
}

import Foundation
import GIMClientKit
import Observation

/// Mirrors gim-core's chat list and connection state. gim-core serves the list from its database, so this works
/// offline; sync is the core's job.
@MainActor
@Observable
public final class ChatListViewModel {
    public private(set) var rows: [ChatRow] = []
    public private(set) var connectionState: ConnectionState = .online
    /// True until the first chat list arrives.
    public private(set) var isLoading = true
    /// Set when subscribing failed.
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI
    private let dateFormatter: RelativeDateFormatter
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?

    public init(client: any GimClientAPI, dateFormatter: RelativeDateFormatter = RelativeDateFormatter()) {
        self.client = client
        self.dateFormatter = dateFormatter
    }

    deinit {
        listTask?.cancel()
        connectionTask?.cancel()
    }

    /// Subscribes to the chat list and the connection state. Does nothing while already subscribed.
    public func start() {
        guard listTask == nil else { return }
        errorMessage = nil
        let client = client
        listTask = Task { [weak self] in
            do {
                for await diffs in try await ListenerBridge.chatList(client) {
                    self?.apply(diffs)
                }
            } catch {
                self?.fail(error)
            }
        }
        connectionTask = Task { [weak self] in
            do {
                for await state in try await ListenerBridge.connection(client) {
                    self?.connectionState = state
                }
            } catch {
                self?.fail(error)
            }
        }
    }

    /// Cancels both subscriptions.
    public func stop() {
        listTask?.cancel()
        connectionTask?.cancel()
        listTask = nil
        connectionTask = nil
    }

    /// Subscribes again; the new subscription starts with a full reset.
    public func refresh() {
        stop()
        start()
    }

    private func apply(_ diffs: [ChatListDiff]) {
        isLoading = false
        let formatter = dateFormatter
        let rowDiffs = diffs.map { diff -> RowDiff in
            let row = { ChatRow(summary: $0, dateFormatter: formatter) }
            return switch diff.operation {
            case .reset(let items): RowDiff(operation: .reset(items.map(row)))
            case .insert(let index, let item): RowDiff(operation: .insert(index, row(item)))
            case .update(let index, let item): RowDiff(operation: .update(index, row(item)))
            case .remove(let index): RowDiff(operation: .remove(index))
            }
        }
        do {
            try DiffApplier.apply(rowDiffs, to: &rows)
        } catch {
            // Out of sync with the core; a new subscription starts with a reset.
            refresh()
        }
    }

    private func fail(_ error: any Error) {
        isLoading = false
        errorMessage = ErrorPresenter.message(for: error)
    }
}

private struct RowDiff: ListDiff {
    let operation: ListOperation<ChatRow>
}

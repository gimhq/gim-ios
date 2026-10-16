import Foundation
import GIMClientKit
import Observation

/// Finds a user by exact handle (debounced) and starts a direct chat with them.
@MainActor
@Observable
public final class NewChatViewModel {
    public enum SearchState: Sendable, Hashable {
        case idle
        case searching
        case found(UserProfile)
        case notFound
        case error(String)
    }

    public static let defaultDebounce: Duration = .milliseconds(300)
    /// `createDirectChat` fails with `NotFound` when the user does not exist or has no device.
    public static let notFoundMessage = "User not found"

    /// Typing restarts the debounced search.
    public var query = "" {
        didSet {
            if query != oldValue { scheduleSearch() }
        }
    }
    public private(set) var state: SearchState = .idle
    public private(set) var isStarting = false
    /// Error from the last failed `startChat()`.
    public private(set) var startError: String?

    private let client: any GimClientAPI
    private let debounce: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// - Parameter sleep: waits out the debounce; must throw when the waiting task is cancelled.
    public init(
        client: any GimClientAPI,
        debounce: Duration = NewChatViewModel.defaultDebounce,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.client = client
        self.debounce = debounce
        self.sleep = sleep
    }

    deinit {
        searchTask?.cancel()
    }

    /// Starts (or reopens) the direct chat with the found user. Returns `nil` on failure.
    public func startChat() async -> String? {
        guard case .found(let user) = state, !isStarting else { return nil }
        isStarting = true
        startError = nil
        defer { isStarting = false }
        do {
            return try await client.createDirectChat(userId: user.userId)
        } catch GimError.NotFound {
            startError = Self.notFoundMessage
            return nil
        } catch {
            startError = ErrorPresenter.message(for: error)
            return nil
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        startError = nil
        let handle = OnboardingValidation.normalizedHandle(query)
        guard !handle.isEmpty else {
            searchTask = nil
            state = .idle
            return
        }
        state = .searching
        let client = client
        let debounce = debounce
        let sleep = sleep
        searchTask = Task { [weak self] in
            do {
                try await sleep(debounce)
                let user = try await client.findUser(handle: handle)
                guard !Task.isCancelled else { return }
                self?.state = user.map(SearchState.found) ?? .notFound
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .error(ErrorPresenter.message(for: error))
            }
        }
    }
}

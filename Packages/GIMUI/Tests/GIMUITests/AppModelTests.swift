import Foundation
import GIMClientKit
import XCTest

@testable import GIMUI

final class AppModelTests: XCTestCase {
    private final class MemoryStorage: SecureStorage, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Data] = [:]
        func get(key: String) throws -> Data? { lock.withLock { values[key] } }
        func set(key: String, value: Data) throws { lock.withLock { values[key] = value } }
        func delete(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
    }

    private struct ClientFactory: GimClientFactory {
        let client: FakeGimClient
        func make(hooks: PlatformHooks) async throws -> any GimClientAPI { client }
    }

    @MainActor
    private func makeModel(client: FakeGimClient) -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        return AppModel(factory: ClientFactory(client: client)) {
            PlatformHooks(secureStorage: MemoryStorage(), dataDirectory: directory)
        }
    }

    @MainActor
    func testUnregisteredClientShowsOnboardingAndRegistrationShowsReady() async throws {
        let model = makeModel(client: FakeGimClient())
        await model.start()
        guard case .onboarding = model.phase else { return XCTFail("expected onboarding, got \(model.phase)") }

        let onboarding = try XCTUnwrap(model.onboarding)
        onboarding.serverUrl = "http://192.168.1.20:8080"
        onboarding.handle = "alex"
        onboarding.displayName = "Alex"
        await onboarding.submit()

        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
        XCTAssertEqual(model.session?.handle, "alex")
    }

    @MainActor
    func testSignOutReturnsToOnboarding() async throws {
        let session = Session(
            userId: "user-alex", deviceId: "device-1", handle: "alex", displayName: "Alex",
            serverUrl: "https://gim.example.eu")
        let model = makeModel(client: FakeGimClient(session: session))
        await model.start()
        XCTAssertEqual(model.session, session)

        let error = await model.signOut()

        XCTAssertNil(error)
        XCTAssertNil(model.session)
        guard case .onboarding = model.phase else { return XCTFail("expected onboarding, got \(model.phase)") }
    }
}

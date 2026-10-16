import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class PushRegistrarTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "PushRegistrarTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    func testRegistersOnlyForTheSimulatorMock() {
        let defaults = makeDefaults()
        for provider in [nil, "", "apns", "fcm"] {
            XCTAssertNil(
                PushRegistrar(provider: provider, appId: "im.g.apps", defaults: defaults).registration(),
                String(describing: provider))
        }
        XCTAssertNil(defaults.string(forKey: PushRegistrar.tokenKey))
    }

    func testMockRegistrationKeepsItsToken() throws {
        let defaults = makeDefaults()
        let registration = try XCTUnwrap(
            PushRegistrar(provider: "mock-ios-sim", appId: "im.g.apps", defaults: defaults).registration())
        XCTAssertEqual(registration.provider, "mock-ios-sim")
        XCTAssertEqual(registration.appId, "im.g.apps")
        XCTAssertTrue(registration.token.hasPrefix("sim-"), registration.token)
        XCTAssertEqual(defaults.string(forKey: PushRegistrar.tokenKey), registration.token)

        let again = PushRegistrar(provider: "mock-ios-sim", appId: "im.g.apps", defaults: defaults).registration()
        XCTAssertEqual(again, registration)
    }
}

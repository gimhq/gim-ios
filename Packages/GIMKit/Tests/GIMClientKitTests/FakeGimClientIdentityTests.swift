import Foundation
import XCTest

@testable import GIMClientKit

final class FakeGimClientIdentityTests: XCTestCase {
    private let me = Session(userId: "user-kai", deviceId: "device-1", displayName: "Kai")

    private func makeClient(session: Session? = nil, users: [UserProfile] = []) throws -> FakeGimClient {
        FakeGimClient(dataDirectory: try makeTemporaryDirectory(), users: users, session: session)
    }

    // MARK: - Recovery

    func testRecoveryCodeHasTheCoreFormatAndIsDeterministic() async throws {
        let code = try await makeClient().createIdentity(displayName: "Kai")
        let again = try await makeClient().createIdentity(displayName: "Kai")

        XCTAssertEqual(code, again)
        let groups = code.split(separator: "-", omittingEmptySubsequences: false)
        XCTAssertEqual(groups.map(\.count), Array(repeating: 4, count: 9) + [3])
        let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        XCTAssertTrue(code.filter { $0 != "-" }.allSatisfy(alphabet.contains), code)
        XCTAssertTrue(["0", "8", "G", "R"].contains(code.last), "the last symbol carries 3 zero padding bits")
        XCTAssertEqual(FakeGimClient.normalizedRecoveryCode(code)?.count, 39)
    }

    func testRecoveryCodeEncodesBytesMostSignificantBitFirst() {
        XCTAssertEqual(
            FakeGimClient.recoveryCode(bytes: Array(repeating: 0xFF, count: 24)),
            "ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZR")
        XCTAssertEqual(
            FakeGimClient.recoveryCode(bytes: [0x08] + Array(repeating: 0, count: 23)),
            "1000-0000-0000-0000-0000-0000-0000-0000-0000-000")
    }

    func testRecoveryCodeParsingFollowsTheCoreRules() {
        let code = "ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZR"
        XCTAssertEqual(FakeGimClient.normalizedRecoveryCode(code), String(repeating: "Z", count: 38) + "R")
        XCTAssertEqual(
            FakeGimClient.normalizedRecoveryCode("ilo0 " + String(repeating: "z", count: 34) + "\t r"),
            "1100" + String(repeating: "Z", count: 34) + "R")
        XCTAssertNil(FakeGimClient.normalizedRecoveryCode(String(code.dropLast())), "38 symbols")
        XCTAssertNil(FakeGimClient.normalizedRecoveryCode(String(code.dropLast()) + "S"), "non-zero padding bits")
        XCTAssertNil(FakeGimClient.normalizedRecoveryCode(String(code.dropLast()) + "U"), "U is not in the alphabet")
    }

    func testRestoreFromRecoveryAcceptsTheLastCodeOfTheUser() async throws {
        let client = try makeClient()
        let code = try await client.createIdentity(displayName: "Kai")
        let createdValue = try await client.session()
        let created = try XCTUnwrap(createdValue)
        XCTAssertEqual(try client.recoveryCode(), code, "createIdentity keeps the code on this device")
        await assertThrows(.InvalidInput(reason: "This device already has an identity")) {
            try await client.restoreFromRecovery(userId: created.userId, recoveryCode: code, revokeOthers: false)
        }
        try await client.signOut()

        await assertThrows(.InvalidInput(reason: "Malformed recovery code")) {
            try await client.restoreFromRecovery(userId: created.userId, recoveryCode: "1234", revokeOthers: false)
        }
        await assertThrows(.NotFound(reason: "device list of user-nobody")) {
            try await client.restoreFromRecovery(userId: "user-nobody", recoveryCode: code, revokeOthers: false)
        }
        let wrong = FakeGimClient.recoveryCode(bytes: Array(repeating: 0, count: 24))
        await assertThrows(.Crypto(reason: "Wrong recovery code")) {
            try await client.restoreFromRecovery(userId: created.userId, recoveryCode: wrong, revokeOthers: false)
        }
        XCTAssertNil(client.userId())

        try await client.restoreFromRecovery(
            userId: created.userId, recoveryCode: code.lowercased().replacingOccurrences(of: "-", with: " "),
            revokeOthers: false)

        let restoredValue = try await client.session()
        let restored = try XCTUnwrap(restoredValue)
        XCTAssertEqual(restored.userId, created.userId)
        XCTAssertEqual(restored.displayName, "Kai")
        XCTAssertEqual(
            try client.recoveryCode().flatMap(FakeGimClient.normalizedRecoveryCode),
            FakeGimClient.normalizedRecoveryCode(code), "restoreFromRecovery keeps the code on this device")
        XCTAssertNotEqual(restored.deviceId, created.deviceId)
        XCTAssertEqual(client.userId(), created.userId)
        let devices = try await client.devices()
        XCTAssertEqual(devices.map(\.deviceId), [created.deviceId, restored.deviceId])
        XCTAssertEqual(devices.map(\.isCurrent), [false, true])
        XCTAssertEqual(devices.map(\.revoked), [false, false])
    }

    func testRestoreCanRevokeTheOtherDevices() async throws {
        let client = try makeClient()
        let code = try await client.createIdentity(displayName: "Kai")
        let userId = try XCTUnwrap(client.userId())
        try await client.signOut()

        try await client.restoreFromRecovery(userId: userId, recoveryCode: code, revokeOthers: true)

        let devices = try await client.devices()
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0], DeviceInfo(deviceId: "device-1", createdAtMs: 0, isCurrent: false, revoked: true))
        XCTAssertTrue(devices[1].isCurrent)
        XCTAssertFalse(devices[1].revoked)
    }

    // MARK: - Devices

    func testDevicesListsTheCurrentAndARevocableDevice() async throws {
        let client = try makeClient(session: me)
        await assertThrows(.NotRegistered) { try await makeClient().devices() }

        let devices = try await client.devices()
        XCTAssertEqual(devices.map(\.deviceId), ["device-1", FakeGimClient.fakeOtherDeviceId])
        XCTAssertEqual(devices.map(\.isCurrent), [true, false])
        XCTAssertTrue(devices.allSatisfy { !$0.revoked && $0.createdAtMs > 0 })

        await assertThrows(.InvalidInput(reason: "The current device can't be revoked")) {
            try await client.revokeDevice(deviceId: "device-1")
        }
        await assertThrows(.NotFound(reason: "device device-x")) {
            try await client.revokeDevice(deviceId: "device-x")
        }
        try await client.revokeDevice(deviceId: FakeGimClient.fakeOtherDeviceId)

        let after = try await client.devices()
        XCTAssertEqual(
            after.last,
            DeviceInfo(deviceId: FakeGimClient.fakeOtherDeviceId, createdAtMs: 0, isCurrent: false, revoked: true))
    }

    func testUserDevicesOfOthersHaveNoCurrentDevice() async throws {
        let client = try makeClient(session: me)
        let own = try await client.userDevices(userId: me.userId)
        XCTAssertEqual(own.map(\.isCurrent), [true, false])
        let unknown = try await client.userDevices(userId: "user-nobody")
        XCTAssertEqual(unknown, [])
    }

    // MARK: - Profile

    func testDisplayNameChanges() async throws {
        let client = try makeClient(
            session: me, users: [UserProfile(userId: "user-sofia", displayName: "Sofia")])
        await assertThrows(.InvalidInput(reason: "Display name is required")) {
            try await client.setDisplayName(name: "  ")
        }
        try await client.setDisplayName(name: " Kai Weber ")

        let session = try await client.session()
        XCTAssertEqual(session, Session(userId: me.userId, deviceId: me.deviceId, displayName: "Kai Weber"))
    }

    // MARK: - Device link

    func testLinkOnTheNewDeviceSignsInAsTheDemoUser() async throws {
        let client = try makeClient()
        await assertThrows(.InvalidInput(reason: "No device link to confirm")) {
            try await client.confirmLink(accepted: true)
        }
        let link = try client.startLink(hubs: ["https://hub.example.eu"])
        XCTAssertTrue(link.qrString().hasPrefix(FakeGimClient.linkQrPrefix))

        let sas = try await client.waitLink(link: link)

        XCTAssertEqual(sas, FakeGimClient.fakeSas)
        XCTAssertEqual(sas, "123 456")
        let sessionValue = try await client.session()
        let session = try XCTUnwrap(sessionValue)
        XCTAssertEqual(session.userId, FakeGimClient.demoSelfId)
        XCTAssertEqual(client.userId(), FakeGimClient.demoSelfId)
        XCTAssertThrowsError(try client.startLink(hubs: [])) {
            XCTAssertEqual($0 as? GimError, .InvalidInput(reason: "This device already has an identity"))
        }
        try await client.confirmLink(accepted: true)
        let devices = try await client.devices()
        XCTAssertEqual(devices.map(\.deviceId), ["device-1", session.deviceId])
        XCTAssertEqual(devices.map(\.isCurrent), [false, true])
        await assertThrows(.InvalidInput(reason: "No device link to confirm")) {
            try await client.confirmLink(accepted: true)
        }
    }

    func testRejectedLinkWipesTheNewDeviceAndALinkIsSingleUse() async throws {
        let client = try makeClient()
        let link = try client.startLink(hubs: ["https://hub.example.eu"])
        _ = try await client.waitLink(link: link)

        try await client.confirmLink(accepted: false)

        let session = try await client.session()
        XCTAssertNil(session)
        XCTAssertNil(client.userId())
        await assertThrows(.InvalidInput(reason: "Start a new device link")) { try await client.waitLink(link: link) }
        await assertThrows(.InvalidInput(reason: "Start a new device link")) {
            try await client.waitLink(link: FakeLinkSession(qrString: "gim-link:fake:99"))
        }
        let next = try client.startLink(hubs: ["https://hub.example.eu"])
        XCTAssertNotEqual(next.qrString(), link.qrString())
        let sas = try await client.waitLink(link: next)
        XCTAssertEqual(sas, FakeGimClient.fakeSas)
    }

    func testUnregisteredDemoSeedsChatsOnceTheLinkIsConfirmed() async throws {
        let client = FakeGimClient.demo(
            scheduler: ManualFakeScheduler(), dataDirectory: try makeTemporaryDirectory(), registered: false)
        _ = try await client.waitLink(link: try client.startLink(hubs: ["https://hub.example.eu"]))
        await assertThrows(.NotFound(reason: "chat \(FakeGimClient.demoGroupChatId)")) {
            try await client.chatMembers(chatId: FakeGimClient.demoGroupChatId)
        }

        try await client.confirmLink(accepted: true)

        let members = try await client.chatMembers(chatId: FakeGimClient.demoGroupChatId)
        XCTAssertEqual(members.first?.userId, FakeGimClient.demoSelfId)
    }

    func testApprovalOnTheOldDeviceAddsOrRevokesTheNewDevice() async throws {
        let newDevice = try makeClient()
        let qrString = try newDevice.startLink(hubs: ["https://hub.example.eu"]).qrString()
        let client = try makeClient(session: me)
        await assertThrows(.NotRegistered) { try await makeClient().approveLink(qrString: qrString) }
        await assertThrows(.InvalidInput(reason: "Not a device link QR code")) {
            try await client.approveLink(qrString: "https://example.eu")
        }

        let accepted = try await client.approveLink(qrString: qrString)
        let rejected = try await client.approveLink(qrString: qrString)

        XCTAssertEqual(accepted.sas(), FakeGimClient.fakeSas)
        XCTAssertNotEqual(accepted.deviceId(), rejected.deviceId())
        try await client.confirmApproval(approval: accepted, accepted: true)
        try await client.confirmApproval(approval: rejected, accepted: false)
        await assertThrows(.InvalidInput(reason: "No pending approval for \(accepted.deviceId())")) {
            try await client.confirmApproval(approval: accepted, accepted: true)
        }
        let devices = try await client.devices()
        XCTAssertEqual(
            devices.map(\.deviceId),
            ["device-1", FakeGimClient.fakeOtherDeviceId, accepted.deviceId(), rejected.deviceId()])
        XCTAssertEqual(devices.map(\.revoked), [false, false, false, true])
    }

    // MARK: - Recovery code on this device

    func testRecoveryCodeIsKeptByRotationAndDroppedBySignOutAndAbsentOnLinkedDevices() async throws {
        let client = try makeClient()
        XCTAssertThrowsError(try client.recoveryCode()) { XCTAssertEqual($0 as? GimError, .NotRegistered) }
        let first = try await client.createIdentity(displayName: "Kai")

        let rotation = try await client.rotateRecoveryCode()

        XCTAssertNotEqual(rotation.recoveryCode, first)
        XCTAssertEqual(try client.recoveryCode(), rotation.recoveryCode)
        try await client.signOut()
        XCTAssertThrowsError(try client.recoveryCode())

        let linked = try makeClient(session: me)
        XCTAssertNil(try linked.recoveryCode(), "a client created with a session (like a linked device) has no code")
    }

    func testRecoveryCodeIsDroppedByDeleteAccount() async throws {
        let client = try makeClient()
        _ = try await client.createIdentity(displayName: "Kai")

        _ = try await client.deleteAccount()

        XCTAssertThrowsError(try client.recoveryCode())
    }
}

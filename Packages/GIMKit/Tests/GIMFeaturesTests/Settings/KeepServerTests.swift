import Foundation
import GIMFeatures
import XCTest

final class KeepServerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testTheBuiltInKeepServerIsTheLastFallback() {
        XCTAssertEqual(KeepServer.builtInUrl, "https://keep.g.im")
        XCTAssertEqual(KeepServer.defaultUrl(argument: nil, bundled: nil), "https://keep.g.im")
        XCTAssertEqual(
            KeepServer.defaultUrl(argument: "", bundled: "  "), "https://keep.g.im", "an unset build setting is empty")
    }

    func testTheArgumentWinsOverTheBundledDefault() {
        XCTAssertEqual(
            KeepServer.defaultUrl(argument: "https://keep.example.eu/", bundled: "https://bundled.example.eu"),
            "https://keep.example.eu")
        XCTAssertEqual(
            KeepServer.defaultUrl(argument: nil, bundled: "https://bundled.example.eu"), "https://bundled.example.eu")
    }

    func testOffAsDefaultMeansNoKeepServer() {
        XCTAssertNil(KeepServer.defaultUrl(argument: "off", bundled: "https://bundled.example.eu"))
        XCTAssertNil(KeepServer.defaultUrl(argument: nil, bundled: "OFF"))
        XCTAssertEqual(
            KeepServer.defaultUrl(argument: "https://keep.example.eu", bundled: "off"), "https://keep.example.eu")
    }

    func testInvalidDefaultsAreSkipped() {
        XCTAssertEqual(
            KeepServer.defaultUrl(argument: "keep.example.eu", bundled: "http://keep.example.eu"), "https://keep.g.im")
        XCTAssertEqual(
            KeepServer.defaultUrl(argument: "$(X)", bundled: "http://localhost:8090"), "http://localhost:8090")
    }

    func testHttpIsOnlyAcceptedOnTheLocalNetwork() {
        for url in [
            "https://keep.example.eu", "http://localhost:8090", "http://127.0.0.1:8090", "http://10.0.0.2",
            "http://192.168.1.20:8090", "http://172.16.0.1", "http://172.31.255.1", "http://169.254.1.1",
            "http://keep.local", "http://[::1]:8090",
        ] {
            XCTAssertNil(KeepServer.urlErrorKind(url), url)
        }
        for url in ["http://keep.example.eu", "http://172.32.0.1", "http://8.8.8.8", "http://192.168.1"] {
            XCTAssertEqual(KeepServer.urlErrorKind(url), .notSecure, url)
        }
        XCTAssertEqual(KeepServer.urlErrorKind("  "), .empty)
        XCTAssertEqual(KeepServer.urlErrorKind("keep.example.eu"), .notAFullAddress)
        XCTAssertEqual(KeepServer.urlErrorKind("ftp://keep.example.eu"), .notAFullAddress)
        XCTAssertFalse(KeepServer.UrlError.notSecure.text.isEmpty)
    }

    func testTheSettingPicksTheUrl() {
        XCTAssertEqual(KeepServer.url(for: .automatic, defaultUrl: "https://keep.g.im"), "https://keep.g.im")
        XCTAssertNil(KeepServer.url(for: .automatic, defaultUrl: nil))
        XCTAssertEqual(
            KeepServer.url(for: .custom("https://keep.example.eu"), defaultUrl: nil), "https://keep.example.eu")
        XCTAssertNil(KeepServer.url(for: .off, defaultUrl: "https://keep.g.im"))
    }

    func testTheSettingIsStoredAndLoaded() {
        XCTAssertEqual(KeepServer.load(from: defaults), .automatic)
        KeepServer.store(.custom("https://keep.example.eu"), in: defaults)
        XCTAssertEqual(KeepServer.load(from: defaults), .custom("https://keep.example.eu"))
        KeepServer.store(.off, in: defaults)
        XCTAssertEqual(KeepServer.load(from: defaults), .off)
        KeepServer.store(.automatic, in: defaults)
        XCTAssertNil(defaults.object(forKey: KeepServer.settingKey))
        XCTAssertEqual(KeepServer.load(from: defaults), .automatic)
    }

    func testAnInvalidStoredSettingLoadsAsAutomatic() {
        defaults.set("http://keep.example.eu", forKey: KeepServer.settingKey)
        XCTAssertEqual(KeepServer.load(from: defaults), .automatic)
    }

    func testTheStoredSettingWinsOverTheDefaults() {
        defaults.set("https://argument.example.eu", forKey: KeepServer.defaultUrlKey)
        XCTAssertEqual(
            KeepServer.resolvedUrl(defaults: defaults, bundled: "https://bundled.example.eu"),
            "https://argument.example.eu")
        KeepServer.store(.custom("https://keep.example.eu"), in: defaults)
        XCTAssertEqual(
            KeepServer.resolvedUrl(defaults: defaults, bundled: "https://bundled.example.eu"), "https://keep.example.eu"
        )
        KeepServer.store(.off, in: defaults)
        XCTAssertNil(KeepServer.resolvedUrl(defaults: defaults, bundled: "https://bundled.example.eu"))
    }

    @MainActor
    func testTheViewModelShowsTheDefault() {
        let model = KeepServerViewModel(
            defaults: defaults, defaultUrl: "https://keep.g.im", activeUrl: "https://keep.g.im")
        XCTAssertTrue(model.isOn)
        XCTAssertTrue(model.isDefault)
        XCTAssertEqual(model.url, "https://keep.g.im")
        XCTAssertEqual(model.draft, "https://keep.g.im")
        XCTAssertFalse(model.needsRestart)
    }

    @MainActor
    func testSavingACustomAddressStoresItAndAsksForARestart() {
        let model = KeepServerViewModel(
            defaults: defaults, defaultUrl: "https://keep.g.im", activeUrl: "https://keep.g.im")
        model.draft = " https://keep.example.eu/ "
        XCTAssertTrue(model.save())
        XCTAssertEqual(model.setting, .custom("https://keep.example.eu"))
        XCTAssertEqual(model.draft, "https://keep.example.eu")
        XCTAssertEqual(KeepServer.load(from: defaults), .custom("https://keep.example.eu"))
        XCTAssertFalse(model.isDefault)
        XCTAssertTrue(model.needsRestart)
    }

    @MainActor
    func testSavingTheDefaultAddressStoresAutomatic() {
        KeepServer.store(.custom("https://keep.example.eu"), in: defaults)
        let model = KeepServerViewModel(defaults: defaults, defaultUrl: "https://keep.g.im", activeUrl: nil)
        model.draft = "https://keep.g.im"
        XCTAssertTrue(model.save())
        XCTAssertEqual(model.setting, .automatic)
        XCTAssertNil(defaults.object(forKey: KeepServer.settingKey))
    }

    @MainActor
    func testAnInvalidAddressIsRefusedAndNothingIsStored() {
        let model = KeepServerViewModel(
            defaults: defaults, defaultUrl: "https://keep.g.im", activeUrl: "https://keep.g.im")
        model.draft = "http://keep.example.eu"
        XCTAssertFalse(model.save())
        XCTAssertEqual(model.errorKind, .notSecure)
        XCTAssertEqual(model.setting, .automatic)
        XCTAssertNil(defaults.object(forKey: KeepServer.settingKey))
        model.draft = "https://keep.example.eu"
        XCTAssertTrue(model.save())
        XCTAssertNil(model.errorKind)
    }

    @MainActor
    func testResetGoesBackToTheDefault() {
        KeepServer.store(.custom("https://keep.example.eu"), in: defaults)
        let model = KeepServerViewModel(
            defaults: defaults, defaultUrl: "https://keep.g.im", activeUrl: "https://keep.example.eu")
        XCTAssertEqual(model.draft, "https://keep.example.eu")
        model.resetToDefault()
        XCTAssertEqual(model.setting, .automatic)
        XCTAssertEqual(model.draft, "https://keep.g.im")
        XCTAssertNil(defaults.object(forKey: KeepServer.settingKey))
        XCTAssertTrue(model.needsRestart)
    }

    @MainActor
    func testTurningItOffAndOnAgain() {
        let model = KeepServerViewModel(
            defaults: defaults, defaultUrl: "https://keep.g.im", activeUrl: "https://keep.g.im")
        model.setOn(false)
        XCTAssertFalse(model.isOn)
        XCTAssertEqual(KeepServer.load(from: defaults), .off)
        XCTAssertTrue(model.needsRestart)
        model.setOn(true)
        XCTAssertEqual(model.setting, .automatic)
        XCTAssertEqual(model.url, "https://keep.g.im")
        XCTAssertFalse(model.needsRestart)
    }

    @MainActor
    func testTurningItOnWithoutADefaultUsesTheBuiltInServer() {
        let model = KeepServerViewModel(defaults: defaults, defaultUrl: nil, activeUrl: nil)
        XCTAssertFalse(model.isOn)
        XCTAssertEqual(model.draft, "https://keep.g.im")
        model.setOn(true)
        XCTAssertEqual(model.setting, .custom("https://keep.g.im"))
        XCTAssertTrue(model.needsRestart)
        model.resetToDefault()
        XCTAssertFalse(model.isOn)
        XCTAssertFalse(model.needsRestart)
    }
}

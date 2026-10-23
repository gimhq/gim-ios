import UIKit
import XCTest

@testable import GIMUI

final class ChatColorsTests: XCTestCase {
    private static let fixedNames = ["BubbleOwn", "BubbleOther", "ReadTicks", "UnreadBadge"]

    func testEveryNamedColorIsInTheCatalog() {
        let names = Self.fixedNames + (0..<ChatColors.avatarCount).map { "Avatar\($0)" }
        for name in names {
            XCTAssertNotNil(UIColor(named: name, in: .module, compatibleWith: nil), "missing color set \(name)")
        }
    }

    func testOwnBubbleDiffersBetweenLightAndDark() {
        let light = ChatColors.UI.bubbleOwn.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = ChatColors.UI.bubbleOwn.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotEqual(light, dark)
    }
}

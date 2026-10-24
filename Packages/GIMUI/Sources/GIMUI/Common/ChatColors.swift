import SwiftUI
import UIKit

/// Chat colors from `Resources/Colors.xcassets`, each with a light and a dark variant: the bubbles, the read ticks,
/// the unread badge and the eight avatar hues.
enum ChatColors {
    static let bubbleOwn = Color("BubbleOwn", bundle: .module)
    static let bubbleOther = Color("BubbleOther", bundle: .module)
    static let readTicks = Color("ReadTicks", bundle: .module)
    static let unreadBadge = Color("UnreadBadge", bundle: .module)
    static let avatarCount = 8

    static func avatar(_ index: Int) -> Color {
        Color("Avatar\(index)", bundle: .module)
    }

    /// UIKit twins for the collection view cells, resolved from the same catalog.
    enum UI {
        static let bubbleOwn = named("BubbleOwn")
        static let bubbleOther = named("BubbleOther")
        static let readTicks = named("ReadTicks")
        static let unreadBadge = named("UnreadBadge")

        static func avatar(_ index: Int) -> UIColor {
            named("Avatar\(index)")
        }

        private static func named(_ name: String) -> UIColor {
            UIColor(named: name, in: .module, compatibleWith: nil)!
        }
    }
}

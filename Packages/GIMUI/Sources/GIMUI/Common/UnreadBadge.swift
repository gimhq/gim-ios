import SwiftUI

/// Capsule with the unread count; renders nothing for zero.
public struct UnreadBadge: View {
    let count: UInt32

    public init(count: UInt32) {
        self.count = count
    }

    public var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(.tint))
                .accessibilityLabel("\(count) unread")
        }
    }
}

#Preview {
    HStack {
        UnreadBadge(count: 3)
        UnreadBadge(count: 120)
    }
}

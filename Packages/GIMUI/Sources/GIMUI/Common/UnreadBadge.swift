import SwiftUI

/// Capsule with the unread count; renders nothing for zero.
public struct UnreadBadge: View {
    let count: UInt32

    @ScaledMetric(relativeTo: .caption) private var minSize: CGFloat = 20

    public init(count: UInt32) {
        self.count = count
    }

    public var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: minSize, minHeight: minSize)
                .background(Capsule().fill(ChatColors.unreadBadge))
                .accessibilityLabel(Text("\(Int(count)) unread", tableName: "Common", bundle: .module))
        }
    }
}

#Preview {
    HStack {
        UnreadBadge(count: 3)
        UnreadBadge(count: 120)
    }
}

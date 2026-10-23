import SwiftUI

/// Circular avatar: the image at `avatarPath`, otherwise initials on a color derived from `id`.
public struct AvatarView: View {
    let id: String
    let name: String
    let avatarPath: String?
    let size: CGFloat

    @Environment(\.imageFileLoader) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    public init(id: String, name: String, avatarPath: String?, size: CGFloat = 40) {
        self.id = id
        self.name = name
        self.avatarPath = avatarPath
        self.size = size
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AvatarStyle.palette[AvatarStyle.colorIndex(for: id)]
                Text(AvatarStyle.initials(for: name))
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: avatarPath) {
            guard let avatarPath else {
                image = nil
                return
            }
            image = await loader.image(atPath: avatarPath, maxPixelSize: size * displayScale)
        }
    }
}

enum AvatarStyle {
    static let palette: [Color] = (0..<ChatColors.avatarCount).map(ChatColors.avatar)

    /// Up to two initials from the first and last words; "?" for an empty name.
    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// Stable across launches (FNV-1a), unlike `hashValue`.
    static func colorIndex(for id: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(palette.count))
    }

    /// The palette color for `id` as a `UIColor`, for the UIKit cells.
    static func uiColor(for id: String) -> UIColor {
        ChatColors.UI.avatar(colorIndex(for: id))
    }
}

#Preview {
    HStack {
        AvatarView(id: "user-sofia", name: "Sofia Marin", avatarPath: nil)
        AvatarView(id: "user-nikos", name: "Nikos", avatarPath: nil, size: 56)
    }
}

import ImageIO
import SwiftUI
import UIKit

/// Decodes downsampled images from local files off the main thread and caches them in memory.
public final class ImageFileLoader: @unchecked Sendable {
    // NSCache is thread-safe; the class holds no other mutable state.
    private let cache = NSCache<NSString, UIImage>()

    public init(countLimit: Int = 200) {
        cache.countLimit = countLimit
    }

    /// Returns the image at `path` scaled so its longest side is at most `maxPixelSize` pixels.
    public func image(atPath path: String, maxPixelSize: CGFloat) async -> UIImage? {
        let key = "\(path)#\(Int(maxPixelSize.rounded(.up)))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decode(path: path, maxPixelSize: maxPixelSize)
        }.value
        if let decoded { cache.setObject(decoded, forKey: key) }
        return decoded
    }

    private static func decode(path: String, maxPixelSize: CGFloat) -> UIImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url, sourceOptions) else { return nil }
        let thumbnailOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: image)
    }
}

private struct ImageFileLoaderKey: EnvironmentKey {
    static let defaultValue = ImageFileLoader()
}

extension EnvironmentValues {
    public var imageFileLoader: ImageFileLoader {
        get { self[ImageFileLoaderKey.self] }
        set { self[ImageFileLoaderKey.self] = newValue }
    }
}

import Foundation

/// Pure rules for outgoing attachments: MIME types, the size limit and the image downscale target.
public enum MediaPreparation {
    /// Largest attachment that can be sent, in bytes (100 MB).
    public static let maxFileSize: UInt64 = 100 * 1024 * 1024
    /// Longest side of a sent image, in pixels.
    public static let maxImagePixelSize = 2048
    /// JPEG quality of re-encoded images.
    public static let imageCompressionQuality = 0.8
    public static let fallbackMimeType = "application/octet-stream"

    static let mimeTypes: [String: String] = [
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "heic": "image/heic",
        "gif": "image/gif",
        "pdf": "application/pdf",
        "zip": "application/zip",
        "txt": "text/plain",
        "mp4": "video/mp4",
        "mov": "video/quicktime",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ]

    /// MIME type for a file extension (case-insensitive, with or without the leading dot).
    public static func mimeType(forExtension fileExtension: String) -> String {
        var key = fileExtension.lowercased()
        if key.hasPrefix(".") { key.removeFirst() }
        return mimeTypes[key] ?? fallbackMimeType
    }

    /// MIME type for a file path, from its extension.
    public static func mimeType(forPath path: String) -> String {
        mimeType(forExtension: URL(fileURLWithPath: path).pathExtension)
    }

    /// Throws `MediaPreparationError.tooLarge` above `maxFileSize`.
    public static func validateSize(_ byteCount: UInt64) throws {
        guard byteCount <= maxFileSize else { throw MediaPreparationError.tooLarge(byteCount: byteCount) }
    }

    /// Size of the file at `path`; throws `MediaPreparationError.unreadable` when it cannot be read.
    public static func fileSize(atPath path: String) throws -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attributes[.size] as? NSNumber
        else { throw MediaPreparationError.unreadable }
        return size.uint64Value
    }

    /// Pixel size of a sent image: the longest side at most `maxLongestSide`, keeping the aspect ratio. Smaller
    /// images keep their size; no side is less than one pixel.
    public static func targetImageSize(
        width: Int, height: Int, maxLongestSide: Int = maxImagePixelSize
    ) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > maxLongestSide, width > 0, height > 0 else { return (width, height) }
        let scale = Double(maxLongestSide) / Double(longest)
        let scaled = { (side: Int) in side == longest ? maxLongestSide : max(1, Int((Double(side) * scale).rounded())) }
        return (scaled(width), scaled(height))
    }
}

public enum MediaPreparationError: Error, Hashable {
    case tooLarge(byteCount: UInt64)
    case unreadable

    /// User-facing text.
    public var message: String {
        kind.text
    }

    /// What the user-facing text says.
    public var kind: MediaPreparationErrorKind {
        switch self {
        case .tooLarge: .tooLarge(limitMegabytes: Int(MediaPreparation.maxFileSize / (1024 * 1024)))
        case .unreadable: .unreadable
        }
    }
}

/// What the error shown for an attachment that can't be sent says.
public enum MediaPreparationErrorKind: Sendable, Hashable {
    /// The file is over the size limit.
    case tooLarge(limitMegabytes: Int)
    case unreadable

    /// The English text, localized through the FeaturesChat table.
    public var text: String {
        switch self {
        case .tooLarge(let limitMegabytes):
            String(
                format: NSLocalizedString(
                    "This file is larger than %lld MB and can't be sent.", tableName: "FeaturesChat",
                    bundle: FeaturesLocalization.bundle, value: "This file is larger than %lld MB and can't be sent.",
                    comment: ""),
                Int64(limitMegabytes))
        case .unreadable:
            NSLocalizedString(
                "This file couldn't be read.", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle,
                value: "This file couldn't be read.", comment: "")
        }
    }
}

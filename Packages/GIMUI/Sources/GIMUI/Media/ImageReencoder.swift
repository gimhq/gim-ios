import Foundation
import GIMFeatures
import ImageIO
import UniformTypeIdentifiers

/// Prepares picked images for sending: downscaled to `MediaPreparation.maxImagePixelSize`, orientation applied,
/// re-encoded as JPEG without the source metadata (EXIF, GPS location).
enum ImageReencoder {
    /// Writes the re-encoded image to a new temporary file and returns its URL. Runs synchronously; call it off the
    /// main thread.
    static func reencode(_ source: URL) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw MediaPreparationError.unreadable }
        // EXIF orientations 5–8 rotate by 90°, swapping the displayed width and height.
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let rotated = orientation >= 5 && orientation <= 8
        let target = MediaPreparation.targetImageSize(
            width: rotated ? pixelHeight : pixelWidth, height: rotated ? pixelWidth : pixelHeight)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw MediaPreparationError.unreadable
        }

        let destinationURL = try TemporaryAttachment.makeURL(fileName: "Photo.jpg")
        guard
            let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw MediaPreparationError.unreadable }
        // Only the quality is passed, so none of the source properties (location included) are written.
        let encoding: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: MediaPreparation.imageCompressionQuality
        ]
        CGImageDestinationAddImage(destination, image, encoding as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            TemporaryAttachment.remove(destinationURL)
            throw MediaPreparationError.unreadable
        }
        return destinationURL
    }
}

/// Outgoing attachments are prepared into their own temporary directory, so the file keeps its name (gim-core sends
/// it as the file name) and can be removed once `sendMedia` has copied it.
enum TemporaryAttachment {
    static func makeURL(fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gim-outgoing", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName.isEmpty ? "File" : fileName)
    }

    /// Removes a file made by `makeURL(fileName:)` together with its directory.
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Copies a picked document to a temporary file, inside its security scope. Refuses files over the size limit
    /// before copying.
    static func copySecurityScoped(_ source: URL) throws -> URL {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        try MediaPreparation.validateSize(try MediaPreparation.fileSize(atPath: source.path))
        let destination = try makeURL(fileName: source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            remove(destination)
            throw MediaPreparationError.unreadable
        }
        return destination
    }
}

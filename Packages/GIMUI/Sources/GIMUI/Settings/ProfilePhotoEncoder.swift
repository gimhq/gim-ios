import CoreGraphics
import Foundation
import GIMFeatures
import ImageIO
import UniformTypeIdentifiers

/// Prepares a picked profile photo: orientation applied, cropped to a centred square of at most
/// `ProfilePhotoViewModel.maxPixelSize` pixels, re-encoded as JPEG without the source metadata (EXIF, GPS location).
enum ProfilePhotoEncoder {
    /// Writes the photo to a new temporary file and returns its URL; remove it with `TemporaryAttachment.remove(_:)`.
    /// Runs synchronously; call it off the main thread.
    static func encode(_ data: Data) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
            pixelWidth > 0, pixelHeight > 0
        else { throw MediaPreparationError.unreadable }
        // Scale so the shorter side is the square's side; the longest side does not depend on the orientation.
        let shorter = min(pixelWidth, pixelHeight)
        let side = min(shorter, ProfilePhotoViewModel.maxPixelSize)
        let longest = (max(pixelWidth, pixelHeight) * side + shorter - 1) / shorter
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw MediaPreparationError.unreadable
        }
        let cropSide = min(scaled.width, scaled.height)
        let square = CGRect(
            x: (scaled.width - cropSide) / 2, y: (scaled.height - cropSide) / 2, width: cropSide, height: cropSide)
        guard let image = scaled.cropping(to: square) else { throw MediaPreparationError.unreadable }

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

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Renders `text` as a QR code, one pixel per module scaled without smoothing so it stays crisp. Exposes `text` as the
/// accessibility value so UI tests can read it.
struct QRCodeView: View {
    let text: String

    var body: some View {
        Group {
            if let image = Self.image(for: text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Link QR code", tableName: "Devices", bundle: .module))
        .accessibilityValue(text)
    }

    private static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
            let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    QRCodeView(text: "gim-link:fake:1").frame(width: 240, height: 240)
}

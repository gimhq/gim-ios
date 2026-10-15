import GIMFeatures
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Picks one image from the photo library (no library permission needed) and re-encodes it with
/// `ImageReencoder`. `onPick` runs on the main actor with the temporary JPEG, which the caller removes with
/// `TemporaryAttachment.remove(_:)`.
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    /// Called when an image was chosen, before it is prepared.
    let onStart: () -> Void
    let onPick: (Result<URL, any Error>) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: PhotoPicker

        init(parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard let provider = results.first?.itemProvider else { return }
            parent.onStart()
            // The file only exists until the handler returns, so it is re-encoded inside it (off the main thread).
            // The handler keeps the coordinator alive after the sheet is gone.
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                let result: Result<URL, any Error> =
                    if let url {
                        Result { try ImageReencoder.reencode(url) }
                    } else {
                        .failure(error ?? MediaPreparationError.unreadable)
                    }
                Task { @MainActor in self.parent.onPick(result) }
            }
        }
    }
}

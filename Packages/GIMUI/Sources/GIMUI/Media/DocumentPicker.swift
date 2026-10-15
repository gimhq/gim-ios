import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Picks one file from Files and copies it, inside its security scope, to a temporary file. `onPick` runs on the
/// main actor with the copy, which the caller removes with `TemporaryAttachment.remove(_:)`.
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    /// Called when a file was chosen, before it is copied.
    let onStart: () -> Void
    let onPick: (Result<URL, any Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            guard let url = urls.first else { return }
            parent.onStart()
            // Copying a large file must not block the main thread; the task keeps the coordinator alive.
            Task {
                let result = await Task.detached { Result { try TemporaryAttachment.copySecurityScoped(url) } }.value
                self.parent.onPick(result)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

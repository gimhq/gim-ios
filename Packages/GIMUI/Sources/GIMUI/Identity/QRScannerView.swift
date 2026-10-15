@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Live camera preview that reports each newly recognised QR code. Requires camera access; check
/// `AVCaptureDevice.authorizationStatus(for: .video)` first.
struct QRScannerView: UIViewRepresentable {
    let onScan: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = context.coordinator.session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.onScan = onScan
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    /// Owns the capture session. The session is configured, started and stopped on `queue` only (starting blocks);
    /// metadata arrives on the main queue.
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        let session = AVCaptureSession()
        @MainActor var onScan: (String) -> Void
        /// The last reported code, so a code held in front of the camera is reported once.
        @MainActor private var lastValue: String?
        private let queue = DispatchQueue(label: "im.g.apps.qr-scanner")
        private var isConfigured = false

        @MainActor
        init(onScan: @escaping @MainActor (String) -> Void) {
            self.onScan = onScan
        }

        func start() {
            queue.async { [self] in
                if !isConfigured {
                    isConfigured = true
                    configure()
                }
                if !session.isRunning { session.startRunning() }
            }
        }

        func stop() {
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
            }
        }

        private func configure() {
            guard let camera = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input)
            else { return }
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.beginConfiguration()
            session.addInput(input)
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            session.commitConfiguration()
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            let values = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            MainActor.assumeIsolated {
                guard let value = values.first, value != lastValue else { return }
                lastValue = value
                onScan(value)
            }
        }
    }
}

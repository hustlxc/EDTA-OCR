@preconcurrency import AVFoundation
import AppKit
import SwiftUI

@MainActor
@Observable
class CameraManager: NSObject {
    var session = AVCaptureSession()
    var isAuthorized = false
    var authorizationChecked = false
    var captureError: String?

    private var photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((NSImage?) -> Void)?

    override init() {
        super.init()
        session.sessionPreset = .photo
    }

    func checkPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
            authorizationChecked = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            authorizationChecked = true
            return granted
        default:
            isAuthorized = false
            authorizationChecked = true
            return false
        }
    }

    func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            captureError = "未检测到摄像头"
            return
        }
        session.addInput(input)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }

    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping (NSImage?) -> Void) {
        captureCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                  didFinishProcessingPhoto photo: AVCapturePhoto,
                                  error: Error?) {
        guard error == nil,
              let cgImage = photo.cgImageRepresentation() else {
            Task { @MainActor [weak self] in
                self?.captureCompletion?(nil)
            }
            return
        }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: size)

        Task { @MainActor [weak self] in
            self?.captureCompletion?(image)
        }
    }
}

// MARK: - Camera Preview (NSViewRepresentable)

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        view.previewLayer?.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        nsView.previewLayer?.frame = nsView.bounds
    }
}

class CameraPreviewView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let layer = previewLayer {
                self.wantsLayer = true
                self.layer?.addSublayer(layer)
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        previewLayer?.frame = self.bounds
    }
}

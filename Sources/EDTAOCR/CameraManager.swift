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
    private var activeCaptureID: UUID?
    private var preferredPhotoDimensions: CMVideoDimensions?

    override init() {
        super.init()
        session.sessionPreset = .photo
        // Stop camera on app quit to release hardware
        let captureSession = session
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in
            captureSession.stopRunning()
        }
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
        if !session.inputs.isEmpty || !session.outputs.isEmpty {
            return
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            captureError = "未检测到摄像头"
            return
        }

        configureCameraDevice(device)

        session.addInput(input)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            if let preferredPhotoDimensions {
                photoOutput.maxPhotoDimensions = preferredPhotoDimensions
            }
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
        guard captureCompletion == nil else {
            completion(nil)
            return
        }

        let captureID = UUID()
        activeCaptureID = captureID
        captureCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.photoQualityPrioritization = .quality
        if let preferredPhotoDimensions {
            settings.maxPhotoDimensions = preferredPhotoDimensions
        }
        photoOutput.capturePhoto(with: settings, delegate: self)

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.activeCaptureID == captureID else { return }
            self.captureError = "拍照超时，请重试"
            self.finishCapture(nil)
        }
    }

    private func configureCameraDevice(_ device: AVCaptureDevice) {
        preferredPhotoDimensions = bestPhotoDimensions(for: device.activeFormat)
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            captureError = "摄像头高清配置失败: \(error.localizedDescription)"
        }
    }

    private func finishCapture(_ image: NSImage?) {
        let completion = captureCompletion
        captureCompletion = nil
        activeCaptureID = nil
        completion?(image)
    }

    private func bestPhotoDimensions(for format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        format.supportedMaxPhotoDimensions.max {
            (Int($0.width) * Int($0.height)) < (Int($1.width) * Int($1.height))
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                  didFinishProcessingPhoto photo: AVCapturePhoto,
                                  error: Error?) {
        guard error == nil,
              let cgImage = photo.cgImageRepresentation() else {
            Task { @MainActor [weak self] in
                self?.finishCapture(nil)
            }
            return
        }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: size)

        Task { @MainActor [weak self] in
            self?.finishCapture(image)
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

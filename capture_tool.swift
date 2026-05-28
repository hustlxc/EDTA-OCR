import AppKit
import AVFoundation
import Vision
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Camera Preview View

class CameraPreviewView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let layer = previewLayer {
                self.layer?.addSublayer(layer)
            }
        }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        previewLayer?.frame = self.bounds
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        previewLayer?.frame = self.bounds
    }
}

// MARK: - Photo Capture Delegate

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let completion: (Result<CGImage, Error>) -> Void

    init(completion: @escaping (Result<CGImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            completion(.failure(error))
            return
        }
        guard let cgImage = photo.cgImageRepresentation() else {
            completion(.failure(NSError(domain: "capture", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从照片数据创建 CGImage"])))
            return
        }
        completion(.success(cgImage))
    }
}

// MARK: - OCR Engine

struct OCRResult: Codable {
    let text: String
    let confidence: Float
    let bbox: [String: Double]
}

func runOCR(on image: CGImage, completion: @escaping ([OCRResult]) -> Void) {
    let request = VNRecognizeTextRequest { request, error in
        guard error == nil,
              let observations = request.results as? [VNRecognizedTextObservation] else {
            completion([])
            return
        }

        let results: [OCRResult] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first,
                  candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
                return nil
            }
            let bbox = obs.boundingBox
            return OCRResult(
                text: candidate.string,
                confidence: candidate.confidence,
                bbox: ["x": Double(bbox.origin.x),
                       "y": Double(bbox.origin.y),
                       "w": Double(bbox.size.width),
                       "h": Double(bbox.size.height)]
            )
        }
        completion(results)
    }

    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.005

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try handler.perform([request])
        } catch {
            completion([])
        }
    }
}

// MARK: - Output helpers

struct CaptureOutput: Codable {
    let success: Bool
    let imagePath: String?
    let error: String?
    let message: String?
    let ocrResults: [OCRResult]?
    let capturedAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case imagePath = "image_path"
        case error
        case message
        case ocrResults = "ocr_results"
        case capturedAt = "captured_at"
    }
}

func outputJSON(_ output: CaptureOutput) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    guard let data = try? encoder.encode(output),
          let json = String(data: data, encoding: .utf8) else {
        let fallback = #"{"success":false,"error":"json_encode_failed","message":"JSON编码失败"}"#
        FileHandle.standardOutput.write(Data(fallback.utf8))
        return
    }
    FileHandle.standardOutput.write(Data(json.utf8))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

// MARK: - Main Application

class CameraApp: NSObject, NSWindowDelegate {
    var window: NSWindow!
    var session: AVCaptureSession!
    var photoOutput: AVCapturePhotoOutput!
    var previewView: CameraPreviewView!
    var overlayLabel: NSTextField!
    var isCapturing = false
    var localEventMonitor: Any?

    func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        checkCameraPermission { granted in
            DispatchQueue.main.async {
                if !granted {
                    outputJSON(CaptureOutput(
                        success: false, imagePath: nil,
                        error: "permission_denied",
                        message: "摄像头权限被拒绝。请在 系统设置 > 隐私与安全性 > 摄像头 中允许访问。",
                        ocrResults: nil, capturedAt: nil
                    ))
                    NSApp.terminate(nil)
                    return
                }
                self.setupUI()
                self.setupCamera()
                app.activate(ignoringOtherApps: true)
                app.run()
            }
        }
    }

    func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        default:
            completion(false)
        }
    }

    func setupUI() {
        let rect = NSRect(x: 0, y: 0, width: 960, height: 720)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EDTA 采血管识别 — 按空格键拍照，按 ESC 退出"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        previewView = CameraPreviewView(frame: rect)
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = previewView

        // Overlay instruction label
        overlayLabel = NSTextField(labelWithString: "按 空格键 拍照    |    按 ESC 退出")
        overlayLabel.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        overlayLabel.textColor = NSColor.white
        overlayLabel.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        overlayLabel.alignment = .center
        overlayLabel.isBezeled = false
        overlayLabel.isEditable = false
        overlayLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayLabel.wantsLayer = true
        overlayLabel.layer?.cornerRadius = 10
        overlayLabel.layer?.masksToBounds = true
        previewView.addSubview(overlayLabel)

        NSLayoutConstraint.activate([
            overlayLabel.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            overlayLabel.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: -40),
            overlayLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 340),
            overlayLabel.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Keyboard monitor
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return nil
        }

        window.makeKeyAndOrderFront(nil)
    }

    func setupCamera() {
        session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async {
                outputJSON(CaptureOutput(
                    success: false, imagePath: nil,
                    error: "no_camera",
                    message: "未检测到摄像头设备",
                    ocrResults: nil, capturedAt: nil
                ))
                NSApp.terminate(nil)
            }
            return
        }

        session.addInput(input)

        photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        DispatchQueue.main.async {
            self.previewView.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
            self.previewView.previewLayer?.videoGravity = .resizeAspectFill
            self.previewView.previewLayer?.frame = self.previewView.bounds
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    func handleKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 49: // Space
            capturePhoto()
        case 53: // ESC
            outputJSON(CaptureOutput(
                success: false, imagePath: nil,
                error: "cancelled",
                message: "用户取消拍照",
                ocrResults: nil, capturedAt: nil
            ))
            cleanupAndExit()
        default:
            break
        }
    }

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true

        DispatchQueue.main.async {
            self.overlayLabel.stringValue = "正在处理 OCR ..."
            self.overlayLabel.textColor = NSColor.yellow
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        let delegate = PhotoCaptureDelegate { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let cgImage):
                    self?.processCapturedImage(cgImage)
                case .failure(let error):
                    outputJSON(CaptureOutput(
                        success: false, imagePath: nil,
                        error: "capture_failed",
                        message: "拍照失败: \(error.localizedDescription)",
                        ocrResults: nil, capturedAt: nil
                    ))
                    self?.cleanupAndExit()
                }
            }
        }

        // Must keep a strong reference to delegate until callback completes
        objc_setAssociatedObject(photoOutput!, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        photoOutput!.capturePhoto(with: settings, delegate: delegate)
    }

    func processCapturedImage(_ cgImage: CGImage) {
        // Save to temp file
        let tempDir = NSTemporaryDirectory()
        let imagePath = "\(tempDir)edta_capture_\(UUID().uuidString).png"
        let url = URL(fileURLWithPath: imagePath)

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            outputJSON(CaptureOutput(
                success: false, imagePath: nil,
                error: "save_failed",
                message: "无法保存拍摄照片",
                ocrResults: nil, capturedAt: nil
            ))
            cleanupAndExit()
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)

        // Run OCR
        runOCR(on: cgImage) { [weak self] results in
            DispatchQueue.main.async {
                let formatter = ISO8601DateFormatter()
                let timestamp = formatter.string(from: Date())

                outputJSON(CaptureOutput(
                    success: true,
                    imagePath: imagePath,
                    error: nil,
                    message: nil,
                    ocrResults: results,
                    capturedAt: timestamp
                ))
                self?.cleanupAndExit()
            }
        }
    }

    func cleanupAndExit() {
        session?.stopRunning()
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        window?.close()
        NSApp.terminate(nil)
    }

    // NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        if !isCapturing {
            outputJSON(CaptureOutput(
                success: false, imagePath: nil,
                error: "cancelled",
                message: "用户关闭窗口",
                ocrResults: nil, capturedAt: nil
            ))
        }
        cleanupAndExit()
    }
}

// MARK: - Entry Point

let app = CameraApp()
app.run()

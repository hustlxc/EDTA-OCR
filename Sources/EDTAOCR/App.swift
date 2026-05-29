import SwiftUI
import AppKit

// MARK: - App Entry

@main
struct EDTA_OCR_App: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 960, minHeight: 700)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        appState.camera.session.stopRunning()
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 780)
    }
}

// MARK: - App State

@MainActor
@Observable
class AppState {
    var screen: Screen = .home
    var capturedImage: NSImage?
    var capturedImagePath: String?
    var ocrResults: [OCRItem] = []
    var extractedFields: [String: ExtractedField] = [:]
    var lastSavedRecord: Record?

    // OCR Engine selection
    var ocrEngine: OCREngine = OCREngine.load()
    var paddleOCR: PaddleOCRClient?

    // DeepSeek AI
    var apiKey: String = DeepSeekClient.loadAPIKey() ?? ""
    var isExtractingWithAI = false
    var aiError: String?
    var aiExtractedFields: [String: ExtractedField]?

    let db = DatabaseManager()
    let camera = CameraManager()
    let ocr = OCRProcessor()
    let extractor = FieldExtractor()
    let deepSeek = DeepSeekClient()

    var recordCount: Int { db.count() }
    var hasAPIKey: Bool { !apiKey.isEmpty }
    var paddleOCRAvailable: Bool { paddleOCR?.isReady ?? false }

    enum Screen {
        case home
        case camera
        case review
        case history
    }

    func setOCREngine(_ engine: OCREngine) {
        ocrEngine = engine
        engine.save()
        if engine == .paddleOCR && paddleOCR == nil {
            paddleOCR = PaddleOCRClient()
            Task { await paddleOCR?.start() }
        } else if engine == .vision && paddleOCR != nil {
            paddleOCR?.stop()
            paddleOCR = nil
        }
    }

    /// Run OCR on an image path using the selected engine
    func recognizeOCR(fromPath path: String) async -> [OCRItem] {
        switch ocrEngine {
        case .vision:
            return await ocr.recognize(fromPath: path)
        case .paddleOCR:
            guard let client = paddleOCR, client.isReady else { return [] }
            return await client.recognize(fromPath: path)
        }
    }

    /// Run OCR on an NSImage using the selected engine
    func recognizeOCR(from image: NSImage) async -> [OCRItem] {
        switch ocrEngine {
        case .vision:
            return await ocr.recognize(from: image)
        case .paddleOCR:
            // PP-OCRv5 needs a file path; save to temp first
            guard let path = ocr.saveImageToTemp(image) else { return [] }
            guard let client = paddleOCR, client.isReady else { return [] }
            return await client.recognize(fromPath: path)
        }
    }

    func saveAPIKey(_ key: String) {
        apiKey = key
        DeepSeekClient.saveAPIKey(key)
    }

    func reset() {
        capturedImage = nil
        capturedImagePath = nil
        ocrResults = []
        extractedFields = [:]
        aiExtractedFields = nil
        aiError = nil
        isExtractingWithAI = false
        lastSavedRecord = nil
    }
}

// MARK: - OCR Engine

enum OCREngine: String, CaseIterable {
    case vision = "vision"
    case paddleOCR = "paddleocr"

    var displayName: String {
        switch self {
        case .vision:    return "Mac Vision"
        case .paddleOCR: return "PP-OCRv5"
        }
    }

    var description: String {
        switch self {
        case .vision:    return "系统自带，零依赖，速度快"
        case .paddleOCR: return "PaddleOCR，中文更准，需安装 Python 依赖"
        }
    }

    static func load() -> OCREngine {
        let raw = UserDefaults.standard.string(forKey: "ocr_engine") ?? ""
        return OCREngine(rawValue: raw) ?? .vision
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "ocr_engine")
    }
}

// MARK: - Data types

struct OCRItem: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Float
    let bbox: CGRect
}

struct ExtractedField {
    let value: String
    let confidence: String  // "high" | "medium" | "low"
    let isInferred: Bool    // true = heuristic guess, false = regex match
}

struct Record: Identifiable {
    let id: Int
    let name: String
    let gender: String
    let age: String
    let serialNumber: String
    let bulletNumber: String
    let collectionTime: String
    let department: String
    let bedNumber: String
    let rawOCRText: String
    let savedAt: String
}

// MARK: - Content View (Router)

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            switch state.screen {
            case .home:    HomeView()
            case .camera:  CameraView()
            case .review:  ReviewView()
            case .history: HistoryView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.screen)
    }
}

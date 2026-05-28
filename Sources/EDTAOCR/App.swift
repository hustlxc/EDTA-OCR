import SwiftUI
import AppKit

// MARK: - App Entry

@main
struct EDTA_OCR_App: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 960, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 740)
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

    enum Screen {
        case home
        case camera
        case review
        case history
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
    let collectionTime: String
    let department: String
    let bedNumber: String
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

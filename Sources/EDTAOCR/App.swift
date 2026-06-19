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

    // Qwen VL AI
    var qwenAPIKey: String = QwenVLClient.loadAPIKey() ?? ""
    var qwenModel: QVModel = QVModel.load()
    var isExtractingWithAI = false
    var aiError: String?
    var aiExtractedFields: [String: ExtractedField]?

    let db = DatabaseManager()
    let camera = CameraManager()
    let ocr = OCRProcessor()
    let extractor = FieldExtractor()
    let qwenVL = QwenVLClient()

    // Server connection settings
    var serverURL: String {
        get { UserDefaults.standard.string(forKey: "server_url") ?? "http://172.169.117.199:8087" }
        set { UserDefaults.standard.set(newValue, forKey: "server_url") }
    }
    var serverUser: String {
        get { UserDefaults.standard.string(forKey: "server_user") ?? "edta" }
        set { UserDefaults.standard.set(newValue, forKey: "server_user") }
    }
    var serverPass: String {
        get { UserDefaults.standard.string(forKey: "server_pass") ?? "91342bb" }
        set { UserDefaults.standard.set(newValue, forKey: "server_pass") }
    }
    @ObservationIgnored
    var serverConnected: Bool = false

    func testServerConnection() async -> Bool {
        let ok = await RemoteDB.testConnection()
        serverConnected = ok
        return ok
    }

    // Box position settings
    var firstBoxNumber: Int = UserDefaults.standard.integer(forKey: "first_box_number")
    var firstHolePosition: Int = UserDefaults.standard.integer(forKey: "first_hole_position")

    var minBulletNumber: Int? {
        db.minBulletNumber()
    }

    var recordCount: Int { db.count() }
    var hasQwenAPIKey: Bool { !qwenAPIKey.isEmpty }

    func saveBoxSettings(box: Int, hole: Int) {
        firstBoxNumber = max(1, box)
        firstHolePosition = min(81, max(1, hole))
        UserDefaults.standard.set(firstBoxNumber, forKey: "first_box_number")
        UserDefaults.standard.set(firstHolePosition, forKey: "first_hole_position")
    }

    enum Screen {
        case home
        case camera
        case review
        case history
    }

    func saveQwenAPIKey(_ key: String) {
        qwenAPIKey = key
        QwenVLClient.saveAPIKey(key)
    }

    func recognizeOCR(fromPath path: String) async -> [OCRItem] {
        return await ocr.recognize(fromPath: path)
    }

    func recognizeOCR(from image: NSImage) async -> [OCRItem] {
        return await ocr.recognize(from: image)
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

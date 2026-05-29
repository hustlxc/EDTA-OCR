import Foundation

@MainActor
@Observable
class PaddleOCRClient {
    private var process: Process?

    var isReady = false
    var isLoading = false
    var loadError: String?

    private let reqFile = "/tmp/ocr_request.txt"
    private let respFile = "/tmp/ocr_response.json"
    private let readyFile = "/tmp/ocr_ready"

    func start() async {
        guard process == nil else { return }
        isLoading = true
        loadError = nil

        guard let daemonPath = findDaemonScript() else {
            loadError = "找不到 ocr_daemon.py"
            isLoading = false
            return
        }

        // Clean up previous files
        try? FileManager.default.removeItem(atPath: reqFile)
        try? FileManager.default.removeItem(atPath: respFile)
        try? FileManager.default.removeItem(atPath: readyFile)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-u", daemonPath]
        task.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdinPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        try? task.run()
        process = task

        // Wait for ready file (max 60s for model download)
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: readyFile) {
                isReady = true
                isLoading = false
                return
            }
            // Check for error response
            if FileManager.default.fileExists(atPath: respFile),
               let data = try? Data(contentsOf: URL(fileURLWithPath: respFile)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "error" {
                loadError = json["message"] as? String ?? "PP-OCRv5 启动失败"
                task.terminate(); process = nil
                isLoading = false
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }

        loadError = "PP-OCRv5 启动超时"
        task.terminate(); process = nil
        isLoading = false
    }

    func recognize(fromPath imagePath: String) async -> [OCRItem] {
        guard isReady else { return [] }

        // Clean response
        try? FileManager.default.removeItem(atPath: respFile)

        // Write request
        let cmd = "\(imagePath)\n"
        guard let _ = try? cmd.write(toFile: reqFile, atomically: true, encoding: .utf8) else {
            return []
        }

        // Poll for response (max 30s)
        for _ in 0..<150 {
            if FileManager.default.fileExists(atPath: respFile),
               let data = try? Data(contentsOf: URL(fileURLWithPath: respFile)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                guard json["status"] as? String == "ok",
                      let items = json["results"] as? [[String: Any]] else { return [] }

                return items.compactMap { item in
                    guard let text = item["text"] as? String,
                          let conf = item["confidence"] as? Float else { return nil }
                    let bb = item["bbox"] as? [String: Double] ?? [:]
                    return OCRItem(text: text, confidence: conf,
                                   bbox: CGRect(x: bb["x"] ?? 0, y: bb["y"] ?? 0,
                                                width: bb["w"] ?? 0, height: bb["h"] ?? 0))
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }
        return []
    }

    func stop() {
        // Signal daemon to exit
        try? "exit\n".write(toFile: reqFile, atomically: true, encoding: .utf8)
        process?.terminate()
        process?.waitUntilExit()
        process = nil

        // Clean up
        try? FileManager.default.removeItem(atPath: reqFile)
        try? FileManager.default.removeItem(atPath: respFile)
        try? FileManager.default.removeItem(atPath: readyFile)

        isReady = false; isLoading = false
    }

    private func findDaemonScript() -> String? {
        if let resPath = Bundle.main.resourcePath {
            let p = "\(resPath)/ocr_daemon.py"
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        let cwd = "\(FileManager.default.currentDirectoryPath)/ocr_daemon.py"
        if FileManager.default.fileExists(atPath: cwd) { return cwd }
        return nil
    }
}

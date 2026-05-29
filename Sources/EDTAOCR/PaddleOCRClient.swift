import Foundation

@MainActor
@Observable
class PaddleOCRClient {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var readTask: Task<Void, Never>?

    var isReady = false
    var isLoading = false
    var loadError: String?

    /// Start the Python daemon and wait for "ready" signal
    func start() async {
        guard process == nil else { return }
        isLoading = true
        loadError = nil

        let daemonPath = findDaemonScript()
        guard let daemonPath else {
            loadError = "找不到 ocr_daemon.py"
            isLoading = false
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [daemonPath]
        task.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = FileHandle.nullDevice

        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading

        // Read the first line (ready/error signal)
        let ready = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continuation.resume(returning: false)
                    return
                }
                let status = json["status"] as? String
                if status == "ready" {
                    continuation.resume(returning: true)
                } else if status == "error" {
                    let msg = json["message"] as? String ?? "PP-OCRv5 加载失败"
                    Task { @MainActor [weak self] in self?.loadError = msg }
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }

        if ready {
            try? task.run()
            process = task
            isReady = true
            // Start background reader for subsequent responses
            readTask = Task.detached { [weak self] in
                await self?.readResponses()
            }
        } else {
            task.terminate()
        }
        isLoading = false
    }

    /// Send an image path and wait for OCR results
    func recognize(fromPath imagePath: String) async -> [OCRItem] {
        guard isReady, let stdin, let stdout else { return [] }

        return await withCheckedContinuation { continuation in
            // Write image path to daemon
            let line = "\(imagePath)\n"
            stdin.write(Data(line.utf8))

            // Read response
            stdout.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stdout.readabilityHandler = nil

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["status"] as? String == "ok",
                   let items = json["results"] as? [[String: Any]] {
                    let results: [OCRItem] = items.compactMap { item in
                        guard let text = item["text"] as? String,
                              let confidence = item["confidence"] as? Float else { return nil }
                        let bboxDict = item["bbox"] as? [String: Double] ?? [:]
                        let bbox = CGRect(
                            x: bboxDict["x"] ?? 0,
                            y: bboxDict["y"] ?? 0,
                            width: bboxDict["w"] ?? 0,
                            height: bboxDict["h"] ?? 0
                        )
                        return OCRItem(text: text, confidence: confidence, bbox: bbox)
                    }
                    continuation.resume(returning: results)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func stop() {
        readTask?.cancel()
        readTask = nil

        // Send exit command
        try? stdin?.write(contentsOf: "exit\n".data(using: .utf8)!)
        stdin?.closeFile()
        stdin = nil

        process?.terminate()
        process?.waitUntilExit()
        process = nil
        stdout = nil

        isReady = false
        isLoading = false
    }

    private func readResponses() async {
        // Background task to consume any unexpected daemon output
        // (responses are handled inline in recognize())
    }

    private func findDaemonScript() -> String? {
        let cwd = FileManager.default.currentDirectoryPath
        let path = "\(cwd)/ocr_daemon.py"
        if FileManager.default.fileExists(atPath: path) { return path }
        return nil
    }
}

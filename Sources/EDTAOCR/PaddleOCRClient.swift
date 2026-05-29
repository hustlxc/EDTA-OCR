import Foundation

/// Thread-safe buffer for accumulating FileHandle data in a Sendable closure context.
private final class ReadBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    func extractLine() -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let nl = data.range(of: Data("\n".utf8)) else { return nil }
        let line = data.subdata(in: 0..<nl.lowerBound)
        data.removeSubrange(0...nl.lowerBound)
        return line
    }
}

@MainActor
@Observable
class PaddleOCRClient {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?

    var isReady = false
    var isLoading = false
    var loadError: String?

    func start() async {
        guard process == nil else { return }
        isLoading = true
        loadError = nil

        guard let daemonPath = findDaemonScript() else {
            loadError = "找不到 ocr_daemon.py"
            isLoading = false
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-u", daemonPath]
        task.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading

        try? task.run()
        process = task

        let ready = await readReadyLine(from: stdoutPipe.fileHandleForReading)

        if ready {
            isReady = true
        } else {
            if loadError == nil { loadError = "PP-OCRv5 启动失败" }
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                loadError = (loadError ?? "") + " — \(errStr.prefix(200))"
            }
            task.terminate()
            process = nil; stdin = nil; stdout = nil
        }
        isLoading = false
    }

    private func readReadyLine(from handle: FileHandle) async -> Bool {
        return await withCheckedContinuation { continuation in
            let buffer = ReadBuffer()

            handle.readabilityHandler = { h in
                let chunk = h.availableData
                guard !chunk.isEmpty else { return }
                buffer.append(chunk)

                guard let lineData = buffer.extractLine(),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return // not a complete JSON line yet, or not JSON
                }

                let status = json["status"] as? String
                if status == "ready" {
                    handle.readabilityHandler = nil
                    continuation.resume(returning: true)
                } else if status == "error" {
                    let msg = json["message"] as? String ?? "PP-OCRv5 加载失败"
                    Task { @MainActor [weak self] in self?.loadError = msg }
                    handle.readabilityHandler = nil
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func recognize(fromPath imagePath: String) async -> [OCRItem] {
        guard isReady, let stdin else { return [] }
        _ = stdout?.availableData // flush stale

        return await withCheckedContinuation { continuation in
            let buffer = ReadBuffer()

            stdout?.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                buffer.append(chunk)

                guard let lineData = buffer.extractLine(),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return
                }

                handle.readabilityHandler = nil

                if json["status"] as? String == "ok",
                   let items = json["results"] as? [[String: Any]] {
                    let results: [OCRItem] = items.compactMap { item in
                        guard let text = item["text"] as? String,
                              let conf = item["confidence"] as? Float else { return nil }
                        let bb = item["bbox"] as? [String: Double] ?? [:]
                        return OCRItem(text: text, confidence: conf,
                                       bbox: CGRect(x: bb["x"] ?? 0, y: bb["y"] ?? 0,
                                                    width: bb["w"] ?? 0, height: bb["h"] ?? 0))
                    }
                    continuation.resume(returning: results)
                } else {
                    continuation.resume(returning: [])
                }
            }

            stdin.write(Data("\(imagePath)\n".utf8))
        }
    }

    func stop() {
        try? stdin?.write(contentsOf: "exit\n".data(using: .utf8)!)
        stdin?.closeFile(); stdin = nil
        process?.terminate(); process?.waitUntilExit(); process = nil
        stdout = nil
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

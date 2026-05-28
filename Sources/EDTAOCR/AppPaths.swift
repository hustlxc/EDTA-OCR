import Foundation

enum AppPaths {
    static var storageDirectory: String {
        let envPath = ProcessInfo.processInfo.environment["EDTA_OCR_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let envPath, !envPath.isEmpty {
            ensureDirectory(envPath)
            return envPath
        }

        let cwd = FileManager.default.currentDirectoryPath
        if cwd != "/" {
            ensureDirectory(cwd)
            return cwd
        }

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("EDTAOCR", isDirectory: true)

        let fallback = supportURL?.path ?? NSTemporaryDirectory()
        ensureDirectory(fallback)
        return fallback
    }

    static func path(_ filename: String) -> String {
        "\(storageDirectory)/\(filename)"
    }

    private static func ensureDirectory(_ path: String) {
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

import Foundation

enum AppPaths {
    /// Today's date as "yyyy-MM-dd" (computed once per launch).
    static let today: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }()

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

    /// Returns a path inside the date-stamped subdirectory, e.g. "2026-06-18/edta_ocr.db".
    static func path(_ filename: String) -> String {
        let dir = "\(storageDirectory)/\(today)"
        ensureDirectory(dir)
        return "\(dir)/\(filename)"
    }

    private static func ensureDirectory(_ path: String) {
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

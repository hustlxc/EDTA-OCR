@preconcurrency import Vision
import AppKit
import UniformTypeIdentifiers

struct OCRProcessor: Sendable {
    func recognize(fromPath path: String) async -> [OCRItem] {
        guard let cgImage = loadCGImage(from: path) else { return [] }
        return await recognize(cgImage: cgImage)
    }

    func recognize(from image: NSImage) async -> [OCRItem] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        return await recognize(cgImage: cgImage)
    }

    private func recognize(cgImage: CGImage) async -> [OCRItem] {

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.revision = VNRecognizeTextRequestRevision3
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.005

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    guard let observations = request.results else {
                        continuation.resume(returning: [])
                        return
                    }
                    let results: [OCRItem] = observations.compactMap { obs in
                        guard let candidate = obs.topCandidates(1).first,
                              candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
                            return nil
                        }
                        return OCRItem(
                            text: candidate.string,
                            confidence: candidate.confidence,
                            bbox: obs.boundingBox
                        )
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func loadCGImage(from path: String) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return cgImage
    }

    /// Save to captures/_latest.png for reliable re-reading
    func saveToLatest(_ image: NSImage) -> String? {
        let dir = OCRProcessor.capturesDir
        let path = "\(dir)/_latest.png"
        return writeImage(image, to: path)
    }

    func saveImageToTemp(_ image: NSImage) -> String? {
        return writeImage(image, to: "\(NSTemporaryDirectory())edta_capture_\(UUID().uuidString).png")
    }

    /// Copy the temp image to the captures/ folder, named by serial number.
    /// Returns the destination path on success.
    static let capturesDir: String = {
        let dir = AppPaths.path("captures")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }()

    func saveToCaptures(sourceTempPath: String, serialNumber: String) -> String? {
        let dest = "\(OCRProcessor.capturesDir)/\(serialNumber).png"
        let destURL = URL(fileURLWithPath: dest)

        // If destination already exists, overwrite
        if FileManager.default.fileExists(atPath: dest) {
            try? FileManager.default.removeItem(at: destURL)
        }

        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: sourceTempPath), to: destURL)
            return dest
        } catch {
            print("Failed to copy image to captures/: \(error)")
            return nil
        }
    }

    func deleteImage(serialNumber: String) {
        let path = "\(OCRProcessor.capturesDir)/\(serialNumber).png"
        try? FileManager.default.removeItem(atPath: path)
    }

    func capturedImagePath(serialNumber: String) -> String? {
        let path = "\(OCRProcessor.capturesDir)/\(serialNumber).png"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    func imageExistsInCaptures(serialNumber: String) -> Bool {
        let path = "\(OCRProcessor.capturesDir)/\(serialNumber).png"
        return FileManager.default.fileExists(atPath: path)
    }

    private func writeImage(_ image: NSImage, to path: String) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return path
    }
}

// MARK: - Field Extractor

struct FieldExtractor: Sendable {
    private struct FieldPattern {
        let field: String
        let regex: NSRegularExpression
    }

    private let fieldPatterns: [FieldPattern]
    private let serialRegex: NSRegularExpression
    private let dateRegex: NSRegularExpression
    private let datetimeRegex: NSRegularExpression

    init() {
        let rawPatterns: [(String, [String])] = [
            ("姓名", [
                #"姓名[\s:：]*([^  \t:：]{2,8})"#,
                #"患者[姓名称][\s:：]*([^  \t:：]{2,8})"#,
            ]),
            ("性别", [
                #"性别[\s:：]*([男女])"#,
            ]),
            ("年龄", [
                #"年龄[\s:：]*(\d+)"#,
                #"(\d+)\s*岁"#,
            ]),
            ("科室", [
                #"科室[\s:：]*([^\s:：]{2,12})"#,
            ]),
            ("床号", [
                #"床号[\s:：]*([^\s:：]{1,10})"#,
                #"(\d+[#号]?\s*床)"#,
            ]),
            ("采血时间", [
                #"采血时间[\s:：]*(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2})"#,
                #"采血时间[\s:：]*(\d{4}[-/]\d{1,2}[-/]\d{1,2})"#,
                #"采血日期[\s:：]*(\d{4}[-/]\d{1,2}[-/]\d{1,2})"#,
                #"(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2})"#,
                #"(\d{4}[-/]\d{1,2}[-/]\d{1,2})"#,
            ]),
        ]

        self.fieldPatterns = rawPatterns.flatMap { field, patterns in
            patterns.compactMap { pattern in
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
                return FieldPattern(field: field, regex: regex)
            }
        }

        self.serialRegex = (try? NSRegularExpression(pattern: #"^\d{10,20}$|^[A-Z0-9]{8,20}$"#))
            ?? NSRegularExpression()
        self.datetimeRegex = (try? NSRegularExpression(
            pattern: #"\d{4}[-/]\d{1,2}[-/]\d{1,2}[\sT]\d{1,2}:\d{2}"#
        )) ?? NSRegularExpression()
        self.dateRegex = (try? NSRegularExpression(
            pattern: #"\d{4}[-/]\d{1,2}[-/]\d{1,2}"#
        )) ?? NSRegularExpression()
    }

    // ---- Public ----

    func extract(from items: [OCRItem]) -> [String: ExtractedField] {
        var result = emptyResult()
        let filtered = items.filter { $0.confidence > 0.2 }
        guard !filtered.isEmpty else { return result }

        let rows = groupIntoRows(filtered)
        let fullText = rows.map { row in
            row.sorted { $0.bbox.origin.x < $1.bbox.origin.x }
                .map { $0.text }.joined(separator: "  ")
        }.joined(separator: "\n")
        let nsText = fullText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        var consumedTexts = Set<String>()

        // ---- Pass 1: Regex pattern matching (highest confidence) ----
        for fp in fieldPatterns {
            let key = fp.field
            if result[key]?.value.isEmpty == false { continue }
            if let match = fp.regex.firstMatch(in: fullText, options: [], range: fullRange),
               match.numberOfRanges > 1,
               match.range(at: 1).location != NSNotFound {
                let value = nsText.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    let full = nsText.substring(with: match.range)
                    let conf = estimateConfidence(items: filtered, matchText: full)
                    result[key] = ExtractedField(value: value, confidence: conf, isInferred: false)
                    consumedTexts.insert(full)
                }
            }
        }

        // ---- Pass 2: 住院号 regex ----
        if result["住院号"]?.value.isEmpty ?? true {
            for item in filtered {
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if consumedTexts.contains(text) { continue }
                let r = NSRange(location: 0, length: (text as NSString).length)
                if serialRegex.firstMatch(in: text, options: [], range: r) != nil, text.count >= 8 {
                    let conf = confidenceLevel(item.confidence)
                    result["住院号"] = ExtractedField(value: text, confidence: conf, isInferred: false)
                    consumedTexts.insert(text)
                    break
                }
            }
        }

        // ---- Pass 3: Heuristic inference (fallback for unmatched fields) ----
        let unmatchedItems = filtered.filter {
            !consumedTexts.contains($0.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        inferSerial(&result, from: unmatchedItems, consumed: &consumedTexts)
        inferCollectionTime(&result, from: unmatchedItems, consumed: &consumedTexts)
        inferAge(&result, from: unmatchedItems, consumed: &consumedTexts)
        inferGender(&result, from: unmatchedItems, consumed: &consumedTexts)
        inferBedNumber(&result, from: unmatchedItems, consumed: &consumedTexts)
        inferDepartment(&result, from: unmatchedItems, consumed: &consumedTexts)
        inferName(&result, from: unmatchedItems, consumed: &consumedTexts)

        // Normalize gender
        if let g = result["性别"]?.value {
            if g == "M" || g == "m" { result["性别"] = makeField("男", "medium", inferred: true) }
            if g == "F" || g == "f" { result["性别"] = makeField("女", "medium", inferred: true) }
        }

        return result
    }

    // ---- Inference rules (ordered by specificity, most specific first) ----

    private func inferSerial(_ result: inout [String: ExtractedField],
                             from items: [OCRItem], consumed: inout Set<String>) {
        guard result["住院号"]?.value.isEmpty ?? true else { return }
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if consumed.contains(text) { continue }
            let r = NSRange(location: 0, length: (text as NSString).length)
            if serialRegex.firstMatch(in: text, options: [], range: r) != nil, text.count >= 8 {
                result["住院号"] = makeField(text, confidenceLevel(item.confidence), inferred: true)
                consumed.insert(text)
                return
            }
        }
    }

    private func inferCollectionTime(_ result: inout [String: ExtractedField],
                                     from items: [OCRItem], consumed: inout Set<String>) {
        guard result["采血时间"]?.value.isEmpty ?? true else { return }
        // Try datetime first, then date-only
        let patterns = [datetimeRegex, dateRegex]
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if consumed.contains(text) { continue }
            for regex in patterns {
                let r = NSRange(location: 0, length: (text as NSString).length)
                if regex.firstMatch(in: text, options: [], range: r) != nil {
                    // Additional check: must contain a year (20xx or 19xx)
                    if text.range(of: #"20\d{2}"#, options: .regularExpression) != nil ||
                       text.range(of: #"19\d{2}"#, options: .regularExpression) != nil {
                        result["采血时间"] = makeField(text,
                            confidenceLevel(item.confidence), inferred: true)
                        consumed.insert(text)
                        return
                    }
                }
            }
        }
    }

    private func inferAge(_ result: inout [String: ExtractedField],
                          from items: [OCRItem], consumed: inout Set<String>) {
        guard result["年龄"]?.value.isEmpty ?? true else { return }
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if consumed.contains(text) { continue }
            // Strip "岁" suffix
            let cleaned = text.replacingOccurrences(of: "岁", with: "").trimmingCharacters(in: .whitespaces)
            if let age = Int(cleaned), age > 0, age <= 150, cleaned.count <= 3 {
                // Reject values that look like years or serial fragments
                if age >= 1900 && age <= 2100 { continue }
                result["年龄"] = makeField(String(age), confidenceLevel(item.confidence), inferred: true)
                consumed.insert(text)
                return
            }
        }
    }

    private func inferGender(_ result: inout [String: ExtractedField],
                             from items: [OCRItem], consumed: inout Set<String>) {
        guard result["性别"]?.value.isEmpty ?? true else { return }
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if consumed.contains(text) { continue }
            if text == "男" || text == "女" || text == "M" || text == "F" {
                result["性别"] = makeField(text, confidenceLevel(item.confidence), inferred: true)
                consumed.insert(text)
                return
            }
        }
    }

    private func inferBedNumber(_ result: inout [String: ExtractedField],
                                from items: [OCRItem], consumed: inout Set<String>) {
        guard result["床号"]?.value.isEmpty ?? true else { return }
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if consumed.contains(text) { continue }
            // Ends with 床, or pattern like "12号"
            if text.hasSuffix("床") || text.range(of: #"^\d+[#号]$"#, options: .regularExpression) != nil {
                if text.count <= 10 {
                    result["床号"] = makeField(text, confidenceLevel(item.confidence), inferred: true)
                    consumed.insert(text)
                    return
                }
            }
        }
    }

    private func inferDepartment(_ result: inout [String: ExtractedField],
                                 from items: [OCRItem], consumed: inout Set<String>) {
        guard result["科室"]?.value.isEmpty ?? true else { return }
        let suffixes = ["科", "室", "部", "中心", "门诊", "病区"]
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if consumed.contains(text) { continue }
            // Must be primarily Chinese, 2-10 chars, end with known suffix
            let chineseCount = text.unicodeScalars.filter {
                (0x4E00...0x9FFF).contains($0.value)
            }.count
            if chineseCount >= 2, text.count <= 10,
               suffixes.contains(where: { text.hasSuffix($0) }) {
                result["科室"] = makeField(text, confidenceLevel(item.confidence), inferred: true)
                consumed.insert(text)
                return
            }
        }
    }

    private func inferName(_ result: inout [String: ExtractedField],
                           from items: [OCRItem], consumed: inout Set<String>) {
        guard result["姓名"]?.value.isEmpty ?? true else { return }
        // Last resort: find 2-4 Chinese characters with no digits
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if consumed.contains(text) { continue }
            let hasDigit = text.rangeOfCharacter(from: .decimalDigits) != nil
            let hasLetter = text.range(of: #"[a-zA-Z]"#, options: .regularExpression) != nil
            let chineseOnly = text.unicodeScalars.allSatisfy {
                (0x4E00...0x9FFF).contains($0.value) || CharacterSet.whitespaces.contains($0)
            }
            let chineseCount = text.unicodeScalars.filter {
                (0x4E00...0x9FFF).contains($0.value)
            }.count
            if chineseOnly, chineseCount >= 2, chineseCount <= 4, !hasDigit, !hasLetter {
                result["姓名"] = makeField(text, confidenceLevel(item.confidence), inferred: true)
                consumed.insert(text)
                return
            }
        }
    }

    // ---- Helpers ----

    private func emptyResult() -> [String: ExtractedField] {
        [
            "姓名":     ExtractedField(value: "", confidence: "low", isInferred: false),
            "性别":     ExtractedField(value: "", confidence: "low", isInferred: false),
            "年龄":     ExtractedField(value: "", confidence: "low", isInferred: false),
            "住院号":   ExtractedField(value: "", confidence: "low", isInferred: false),
            "采血时间": ExtractedField(value: "", confidence: "low", isInferred: false),
            "科室":     ExtractedField(value: "", confidence: "low", isInferred: false),
            "床号":     ExtractedField(value: "", confidence: "low", isInferred: false),
        ]
    }

    private func makeField(_ value: String, _ conf: String, inferred: Bool) -> ExtractedField {
        let capped = inferred && conf == "high" ? "medium" : conf
        return ExtractedField(value: value, confidence: capped, isInferred: inferred)
    }

    private func groupIntoRows(_ items: [OCRItem]) -> [[OCRItem]] {
        var rows: [[OCRItem]] = []
        var used = Set<UUID>()
        for (i, item) in items.enumerated() {
            if used.contains(item.id) { continue }
            var row = [item]
            used.insert(item.id)
            for (j, other) in items.enumerated() where j > i && !used.contains(other.id) {
                if abs(other.bbox.origin.y - item.bbox.origin.y) < 0.03 {
                    row.append(other)
                    used.insert(other.id)
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func estimateConfidence(items: [OCRItem], matchText: String) -> String {
        var best: Float = 0
        for item in items {
            if item.text.contains(matchText) || matchText.contains(item.text) {
                if item.confidence > best { best = item.confidence }
            }
        }
        return confidenceLevel(best)
    }

    private func confidenceLevel(_ c: Float) -> String {
        if c > 0.8 { return "high" }
        if c > 0.5 { return "medium" }
        return "low"
    }
}

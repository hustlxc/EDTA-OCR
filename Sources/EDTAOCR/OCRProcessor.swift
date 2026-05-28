@preconcurrency import Vision
import AppKit
import UniformTypeIdentifiers

struct OCRProcessor: Sendable {
    func recognize(from image: NSImage) async -> [OCRItem] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
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

    func saveImageToTemp(_ image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let path = "\(NSTemporaryDirectory())edta_capture_\(UUID().uuidString).png"
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
    private let barcodeRegexes: [NSRegularExpression]

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

        self.barcodeRegexes = [
            #"^\d{10,20}$"#,
            #"^[A-Z0-9]{8,20}$"#,
        ].compactMap { try? NSRegularExpression(pattern: $0) }
    }

    func extract(from items: [OCRItem]) -> [String: ExtractedField] {
        var result: [String: ExtractedField] = [
            "姓名": ExtractedField(value: "", confidence: "low"),
            "性别": ExtractedField(value: "", confidence: "low"),
            "年龄": ExtractedField(value: "", confidence: "low"),
            "barcode": ExtractedField(value: "", confidence: "low"),
            "采血时间": ExtractedField(value: "", confidence: "low"),
            "科室": ExtractedField(value: "", confidence: "low"),
            "床号": ExtractedField(value: "", confidence: "low"),
        ]

        let filtered = items.filter { $0.confidence > 0.2 }
        guard !filtered.isEmpty else { return result }

        let sorted = filtered.sorted { $0.bbox.origin.y > $1.bbox.origin.y }
        let rows = groupIntoRows(sorted)
        let rowTexts = rows.map { row in
            row.map { $0.text }.joined(separator: "  ")
        }
        let fullText = rowTexts.joined(separator: "\n")
        let nsText = fullText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Pass 1: named field patterns
        for fp in fieldPatterns {
            if result[fp.field]?.value.isEmpty == false { continue }
            if let match = fp.regex.firstMatch(in: fullText, options: [], range: fullRange) {
                if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                    let value = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty {
                        let full = nsText.substring(with: match.range)
                        let conf = estimateConfidence(items: filtered, matchText: full)
                        result[fp.field] = ExtractedField(value: value, confidence: conf)
                    }
                }
            }
        }

        // Pass 2: barcode
        for item in filtered {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            for regex in barcodeRegexes {
                let range = NSRange(location: 0, length: (text as NSString).length)
                if regex.firstMatch(in: text, options: [], range: range) != nil, text.count >= 8 {
                    let conf = confidenceLevel(item.confidence)
                    result["barcode"] = ExtractedField(value: text, confidence: conf)
                    break
                }
            }
            if result["barcode"]?.value.isEmpty == false { break }
        }

        // Normalize gender
        if let g = result["性别"]?.value {
            if g == "M" || g == "m" { result["性别"] = ExtractedField(value: "男", confidence: "medium") }
            if g == "F" || g == "f" { result["性别"] = ExtractedField(value: "女", confidence: "medium") }
        }

        return result
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
            row.sort { $0.bbox.origin.x < $1.bbox.origin.x }
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

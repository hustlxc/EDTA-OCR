import Foundation
import AppKit

enum QVModel: String, CaseIterable {
    case vlOCR   = "qwen-vl-ocr"
    case v3Flash = "qwen3-vl-flash"
    case v3Plus  = "qwen3-vl-plus"
    case v36Flash = "qwen3.6-flash"
    case v36Plus = "qwen3.6-plus"

    var displayName: String {
        switch self {
        case .vlOCR:   return "VL OCR (专为OCR优化)"
        case .v3Flash: return "Qwen3-VL Flash (快速)"
        case .v3Plus:  return "Qwen3-VL Plus (均衡)"
        case .v36Flash: return "Qwen3.6 Flash (最新·快)"
        case .v36Plus:  return "Qwen3.6 Plus (最新·强)"
        }
    }

    static func load() -> QVModel {
        QVModel(rawValue: UserDefaults.standard.string(forKey: "qwen_vl_model") ?? "") ?? .v3Flash
    }

    func save() { UserDefaults.standard.set(rawValue, forKey: "qwen_vl_model") }
}

struct QwenVLClient: Sendable {
    private let endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

    struct ExtractedFields: Codable, Sendable {
        let 姓名: String?
        let 性别: String?
        let 年龄: String?
        let 流水号: String?
        let 采血时间: String?
        let 科室: String?
        let 床号: String?
    }

    static func loadAPIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["QWEN_API_KEY"], !env.isEmpty { return env }
        return UserDefaults.standard.string(forKey: "qwen_api_key")
    }

    static func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "qwen_api_key")
    }

    /// Send the captured image directly to Qwen VL for field extraction
    func extract(fromImagePath imagePath: String, apiKey: String, model: QVModel) async throws -> ExtractedFields {
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) else {
            throw QwenVLError.imageLoadFailed
        }
        let base64 = imageData.base64EncodedString()
        let dataURL = "data:image/png;base64,\(base64)"

        let prompt = """
        This is an EDTA blood collection tube label. Extract these fields.
        Return ONLY a JSON object. Use empty string "" if a field is not found.

        姓名: patient name (2-4 Chinese characters)
        性别: gender (男 or 女)
        年龄: age number
        流水号: serial number (long digit/alphanumeric string)
        采血时间: blood collection datetime
        科室: hospital department
        床号: bed number

        Return: {"姓名":"...","性别":"...","年龄":"...","流水号":"...","采血时间":"...","科室":"...","床号":"..."}
        """

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": dataURL]],
                    ["type": "text", "text": prompt],
                ]
            ]],
            "response_format": ["type": "json_object"],
            "temperature": 0.1,
            "max_tokens": 512,
        ]

        let data = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        request.timeoutInterval = 30

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw QwenVLError.invalidResponse
        }
        if http.statusCode == 401 {
            throw QwenVLError.invalidAPIKey
        }
        guard http.statusCode == 200 else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            print("[QwenVL] HTTP \(http.statusCode): \(body)")
            throw QwenVLError.httpError(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: .utf8) else {
            throw QwenVLError.parseError
        }

        return try JSONDecoder().decode(ExtractedFields.self, from: contentData)
    }
}

enum QwenVLError: LocalizedError {
    case invalidAPIKey
    case httpError(Int)
    case invalidResponse
    case parseError
    case imageLoadFailed

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "Qwen API Key 无效"
        case .httpError(let c): return "服务器错误 (HTTP \(c))"
        case .invalidResponse: return "服务器返回异常"
        case .parseError: return "AI 返回格式解析失败"
        case .imageLoadFailed: return "无法读取截图文件"
        }
    }
}

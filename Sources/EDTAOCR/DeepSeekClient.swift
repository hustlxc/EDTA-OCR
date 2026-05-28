import Foundation

struct DeepSeekClient: Sendable {
    private let endpoint = "https://api.deepseek.com/v1/chat/completions"
    private let model = "deepseek-chat"

    struct ExtractedFields: Codable, Sendable {
        let 姓名: String?
        let 性别: String?
        let 年龄: String?
        let 流水号: String?
        let 子弹头编号: String?
        let 采血时间: String?
        let 科室: String?
        let 床号: String?
    }

    /// Read API key from env var or UserDefaults
    static func loadAPIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty {
            return env
        }
        if let saved = UserDefaults.standard.string(forKey: "deepseek_api_key"), !saved.isEmpty {
            return saved
        }
        return nil
    }

    static func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "deepseek_api_key")
    }

    /// Send raw OCR text to DeepSeek and get structured fields back
    func extract(rawText: String, apiKey: String) async throws -> ExtractedFields {
        let prompt = """
        You are extracting fields from an EDTA blood collection tube label OCR result.
        Return ONLY a JSON object with these keys. Use empty string "" if a field is not found.

        Fields:
        - 姓名: patient name (2-4 Chinese characters usually)
        - 性别: gender, 男 or 女 only
        - 年龄: age in years, just the number
        - 流水号: serial number (8-20 digit or alphanumeric, often the longest number)
        - 子弹头编号: bullet tube number (short alphanumeric code, sometimes labeled as 子弹头)
        - 采血时间: blood collection datetime (format: YYYY-MM-DD HH:MM or similar)
        - 科室: department name (ends with 科/室/部/中心 usually)
        - 床号: bed number (ends with 床 or digit+号)

        OCR text from the EDTA tube label:
        \(rawText)

        Return JSON:
        """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a precise medical data extraction tool. Extract exactly what the OCR text contains. Never hallucinate. If unsure, use empty string."],
                ["role": "user", "content": prompt],
            ],
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
        request.timeoutInterval = 60

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw DeepSeekError.requestTimedOut
        } catch {
            throw DeepSeekError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }

        if http.statusCode == 401 {
            throw DeepSeekError.invalidAPIKey
        }
        if http.statusCode == 429 {
            throw DeepSeekError.rateLimited
        }
        guard http.statusCode == 200 else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            print("[DeepSeek] HTTP \(http.statusCode): \(body)")
            throw DeepSeekError.httpError(http.statusCode)
        }

        // Parse OpenAI-compatible response
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            print("[DeepSeek] parse error - body: \(body)")
            throw DeepSeekError.parseError
        }

        if let apiError = json["error"] as? [String: Any],
           let message = apiError["message"] as? String {
            print("[DeepSeek] API error: \(message)")
            throw DeepSeekError.apiError(message)
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("[DeepSeek] unexpected response: \(json)")
            throw DeepSeekError.parseError
        }

        // Parse the content JSON
        guard let contentData = content.data(using: .utf8) else {
            throw DeepSeekError.parseError
        }
        return try JSONDecoder().decode(ExtractedFields.self, from: contentData)
    }
}

enum DeepSeekError: LocalizedError {
    case invalidAPIKey
    case rateLimited
    case httpError(Int)
    case invalidResponse
    case parseError
    case requestTimedOut
    case networkError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "API Key 无效，请检查后重试"
        case .rateLimited:
            return "请求过于频繁，请稍后重试"
        case .httpError(let code):
            return "服务器错误 (HTTP \(code))"
        case .invalidResponse:
            return "服务器返回异常"
        case .parseError:
            return "AI 返回格式解析失败，请重试"
        case .requestTimedOut:
            return "AI 请求超时，请检查网络或稍后重试"
        case .networkError(let msg):
            return "网络错误: \(msg)"
        case .apiError(let msg):
            return "API 错误: \(msg)"
        }
    }
}

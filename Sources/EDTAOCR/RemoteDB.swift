import Foundation


/// Thin HTTP client for the EDTA-OCR web server.
/// Uploads records and images — fire-and-forget, never blocks the UI.
enum RemoteDB {
    static let baseURL = "http://172.169.117.199:8087"

    // Credentials must match WEB_USER / WEB_PASS on the server.
    private static let user = "edta"
    private static let pass = "91342bb"

    // MARK: - Helpers

    private static var authHeader: String {
        let raw = "\(user):\(pass)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private static func postJSON(_ url: URL, _ body: [String: String]) async -> Int? {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? Int {
                return id
            }
        } catch {
            print("[RemoteDB] uploadRecord failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - API

    /// Upload a record (upsert by bullet number). Returns the server-assigned record ID.
    static func uploadRecord(
        name: String, gender: String, age: String,
        serial: String, bullet: String, time: String,
        dept: String, bed: String, ocr: String
    ) async -> Int? {
        guard let url = URL(string: "\(baseURL)/api/records") else { return nil }
        let body: [String: String] = [
            "name": name, "gender": gender, "age": age,
            "serial": serial, "bullet": bullet, "time": time,
            "dept": dept, "bed": bed, "ocr": ocr,
        ]
        return await postJSON(url, body)
    }

    /// Upload a PNG image for an existing record.
    static func uploadImage(recordID: Int, pngURL: URL) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/records/\(recordID)/image"),
              let data = try? Data(contentsOf: pngURL) else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.httpBody = data
        req.timeoutInterval = 15

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[RemoteDB] uploadImage failed: \(error.localizedDescription)")
            return false
        }
    }
}

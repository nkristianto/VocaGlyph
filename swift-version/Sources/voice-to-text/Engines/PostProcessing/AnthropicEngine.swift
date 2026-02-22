import Foundation

/// Errors that can occur during Anthropic engine processing
public enum AnthropicEngineError: LocalizedError, Equatable {
    case missingConfiguration
    case invalidURL
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case invalidResponseFormat
    case contentBlocked
    
    public var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Anthropic API key is not configured. Please add it in Settings."
        case .invalidURL:
            return "The API endpoint URL is invalid."
        case .networkError(let reason):
            return "Network connection failed: \(reason)"
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        case .invalidResponseFormat:
            return "The response from the API was not in the expected format."
        case .contentBlocked:
            return "The request was blocked by safety filters."
        }
    }
}

/// Cloud API Post-Processing Engine using Anthropic's Messages REST API
public actor AnthropicEngine: PostProcessingEngine {
    private let keychainService: KeychainService
    private let session: URLSession
    
    public init(keychainService: KeychainService = KeychainService(), session: URLSession = .shared) {
        self.keychainService = keychainService
        self.session = session
    }
    
    public func refine(text: String, prompt: String) async throws -> String {
        // Fetch API Key
        let apiKey: String
        do {
            apiKey = try await keychainService.readKey(forService: "com.vocaglyph.api.anthropic")
        } catch {
            throw AnthropicEngineError.missingConfiguration
        }
        
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AnthropicEngineError.invalidURL
        }
        
        // Build JSON Payload
        let payload: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 1024,
            "temperature": 0.2,
            "system": prompt, // Pass the user's prompt instruction as the system parameter
            "messages": [
                [
                    "role": "user",
                    "content": text
                ]
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw AnthropicEngineError.invalidResponseFormat
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        // ── Request log ─────────────────────────────────────────────────────
        PostProcessingLogger.shared.info("AnthropicEngine: [REQUEST] POST https://api.anthropic.com/v1/messages")
        PostProcessingLogger.shared.info("AnthropicEngine: [REQUEST] System prompt: '\(prompt)'")
        PostProcessingLogger.shared.info("AnthropicEngine: [REQUEST] Input (\(text.count) chars): '\(text)'")
        if let bodyStr = String(data: jsonData, encoding: .utf8) {
            PostProcessingLogger.shared.info("AnthropicEngine: [REQUEST] Body: \(bodyStr)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
            // ── Response log ───────────────────────────────────────────────
            if let responseString = String(data: data, encoding: .utf8) {
                PostProcessingLogger.shared.info("AnthropicEngine: [RESPONSE] HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(responseString)")
            } else {
                PostProcessingLogger.shared.info("AnthropicEngine: [RESPONSE] Unable to decode response as UTF-8.")
            }
        } catch {
            Logger.shared.error("AnthropicEngine: Network connection failed: \(error.localizedDescription)")
            throw AnthropicEngineError.networkError(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicEngineError.invalidResponseFormat
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            // Attempt to parse error response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw AnthropicEngineError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            throw AnthropicEngineError.apiError(statusCode: httpResponse.statusCode, message: "Unknown API Error")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let extractedText = firstBlock["text"] as? String else {
            throw AnthropicEngineError.invalidResponseFormat
        }

        let result = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        PostProcessingLogger.shared.info("AnthropicEngine: [RESULT] '\(result)'")
        return result
    }
}

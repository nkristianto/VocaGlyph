import Foundation

/// Errors that can occur during Gemini engine processing
public enum GeminiEngineError: LocalizedError, Equatable {
    case missingConfiguration
    case invalidURL
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case invalidResponseFormat
    case contentBlocked
    
    public var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Gemini API key is not configured. Please add it in Settings."
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

/// Cloud API Post-Processing Engine using Google's Gemini REST API
public actor GeminiEngine: PostProcessingEngine {
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
            apiKey = try await keychainService.readKey(forService: "com.vocaglyph.api.gemini")
        } catch {
            throw GeminiEngineError.missingConfiguration
        }
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else {
            throw GeminiEngineError.invalidURL
        }
        
        let fullPrompt = "\(prompt)\n\nOriginal Text: \(text)"
        
        // Build JSON Payload
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw GeminiEngineError.invalidResponseFormat
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // ── Request log ──────────────────────────────────────────────────────────
        PostProcessingLogger.shared.info("GeminiEngine: [REQUEST] POST gemini-2.5-flash:generateContent")
        PostProcessingLogger.shared.info("GeminiEngine: [REQUEST] Prompt: '\(prompt)'")
        PostProcessingLogger.shared.info("GeminiEngine: [REQUEST] Input (\(text.count) chars): '\(text)'")
        if let bodyStr = String(data: jsonData, encoding: .utf8) {
            PostProcessingLogger.shared.info("GeminiEngine: [REQUEST] Body: \(bodyStr)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
            // ── Response log ─────────────────────────────────────────────────────
            if let responseString = String(data: data, encoding: .utf8) {
                PostProcessingLogger.shared.info("GeminiEngine: [RESPONSE] HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(responseString)")
            } else {
                PostProcessingLogger.shared.info("GeminiEngine: [RESPONSE] Unable to decode response as UTF-8.")
            }
        } catch {
            Logger.shared.error("GeminiEngine: Network connection failed: \(error.localizedDescription)")
            throw GeminiEngineError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiEngineError.invalidResponseFormat
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw GeminiEngineError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            throw GeminiEngineError.apiError(statusCode: httpResponse.statusCode, message: "Unknown API Error")
        }

        // Parse successful response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first else {
            throw GeminiEngineError.invalidResponseFormat
        }

        if let finishReason = firstCandidate["finishReason"] as? String,
           finishReason == "SAFETY" || finishReason == "RECITATION" {
            throw GeminiEngineError.contentBlocked
        }

        guard let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let extractedText = firstPart["text"] as? String else {
            throw GeminiEngineError.invalidResponseFormat
        }

        // 1. Strip chatty preambles ("Here is the revised text:", "**Revised Text:**", etc.)
        let sanitized = PostProcessingOutputSanitizer.sanitize(extractedText)

        // 2. Validate for refusals and hallucinations — fall back to raw input if invalid.
        let result: String
        switch PostProcessingOutputSanitizer.validate(sanitized, against: text) {
        case .valid(let cleaned):
            result = cleaned
        case .fallback(let reason):
            PostProcessingLogger.shared.error(
                "GeminiEngine: Output validation failed (\(reason.rawValue)) — using raw transcription"
            )
            result = text
        }

        PostProcessingLogger.shared.info("GeminiEngine: [RESULT] '\(result)'")
        return result
    }
}

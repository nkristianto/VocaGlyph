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
        
        let data: Data
        let response: URLResponse
        do {
            Logger.shared.info("GeminiEngine: Initiating REST call to API provider...")
            (data, response) = try await session.data(for: request)
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.shared.info("GeminiEngine: Received raw JSON: \(responseString)")
            } else {
                Logger.shared.info("GeminiEngine: Received response from API provider (Unable to decode to string).")
            }
        } catch {
            Logger.shared.error("GeminiEngine: Network connection failed: \(error.localizedDescription)")
            throw GeminiEngineError.networkError(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiEngineError.invalidResponseFormat
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            // Attempt to parse error response
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
        
        return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

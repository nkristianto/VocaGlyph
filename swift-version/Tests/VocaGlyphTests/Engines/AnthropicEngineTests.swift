import XCTest
@testable import voice_to_text

final class AnthropicEngineTests: XCTestCase {
    var session: URLSession!
    var keychain: KeychainService!
    let mockKeyService = "com.vocaglyph.api.anthropic"
    
    override func setUp() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
        keychain = KeychainService()
    }
    
    override func tearDown() async throws {
        _ = try? await keychain.deleteKey(forService: mockKeyService)
        MockURLProtocol.requestHandler = nil
    }
    
    func testMissingAPIKeyThrowsError() async {
        let engine = AnthropicEngine(keychainService: keychain, session: session)
        
        // Ensure no key exists
        _ = try? await keychain.deleteKey(forService: mockKeyService)
        
        do {
            _ = try await engine.refine(text: "Hello", prompt: "Translate to French")
            XCTFail("Expected missingConfiguration error")
        } catch let error as AnthropicEngineError {
            XCTAssertEqual(error, .missingConfiguration)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSuccessfulRefineReturnsText() async throws {
        try await keychain.saveKey("test_anthropic_key", forService: mockKeyService)
        
        let expectedJSON = """
        {
          "id": "msg_123",
          "type": "message",
          "role": "assistant",
          "model": "claude-3-5-haiku-20241022",
          "content": [
            {
              "type": "text",
              "text": "Bonjour"
            }
          ]
        }
        """
        
        let responseData = expectedJSON.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString != "https://api.anthropic.com/v1/messages" {
                let errorResponse = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (errorResponse, "error".data(using: .utf8)!)
            }
            if request.httpMethod != "POST" {
                let errorResponse = HTTPURLResponse(url: request.url!, statusCode: 405, httpVersion: nil, headerFields: nil)!
                return (errorResponse, "error".data(using: .utf8)!)
            }
            if request.value(forHTTPHeaderField: "x-api-key") != "test_anthropic_key" {
                let errorResponse = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (errorResponse, "error".data(using: .utf8)!)
            }
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }
        
        let engine = AnthropicEngine(keychainService: keychain, session: session)
        let result = try await engine.refine(text: "Hello", prompt: "Translate to French")
        
        XCTAssertEqual(result, "Bonjour")
    }
    
    func testAPIErrorResponseThrowsError() async throws {
        try await keychain.saveKey("test_anthropic_key", forService: mockKeyService)
        
        let errorJSON = """
        {
          "type": "error",
          "error": {
            "type": "authentication_error",
            "message": "invalid x-api-key"
          }
        }
        """
        let responseData = errorJSON.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }
        
        let engine = AnthropicEngine(keychainService: keychain, session: session)
        
        do {
            _ = try await engine.refine(text: "Hello", prompt: "Translate to French")
            XCTFail("Expected apiError")
        } catch let error as AnthropicEngineError {
            XCTAssertEqual(error, .apiError(statusCode: 401, message: "invalid x-api-key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

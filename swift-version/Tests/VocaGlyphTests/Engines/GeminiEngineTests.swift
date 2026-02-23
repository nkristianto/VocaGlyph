import XCTest
@testable import VocaGlyph

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("No request handler provided.")
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

final class GeminiEngineTests: XCTestCase {
    var session: URLSession!
    var keychain: KeychainService!
    let mockKeyService = "com.vocaglyph.api.gemini"
    
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
        let engine = GeminiEngine(keychainService: keychain, session: session)
        
        // Ensure no key exists (can leak if user actually saved one locally)
        _ = try? await keychain.deleteKey(forService: mockKeyService)
        
        do {
            _ = try await engine.refine(text: "Hello", prompt: "Translate to Japanese")
            XCTFail("Expected missingConfiguration error")
        } catch let error as GeminiEngineError {
            XCTAssertEqual(error, .missingConfiguration)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSuccessfulRefineReturnsText() async throws {
        try await keychain.saveKey("test_api_key", forService: mockKeyService)
        
        let expectedJSON = """
        {
          "candidates": [
            {
              "content": {
                "parts": [
                  {"text": "こんにちは"}
                ]
              },
              "finishReason": "STOP"
            }
          ]
        }
        """
        
        let responseData = expectedJSON.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString != "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=test_api_key" {
                let errorResponse = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (errorResponse, "error".data(using: .utf8)!)
            }
            if request.httpMethod != "POST" {
                let errorResponse = HTTPURLResponse(url: request.url!, statusCode: 405, httpVersion: nil, headerFields: nil)!
                return (errorResponse, "error".data(using: .utf8)!)
            }
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }
        
        let engine = GeminiEngine(keychainService: keychain, session: session)
        let result = try await engine.refine(text: "Hello", prompt: "Translate to Japanese")
        
        XCTAssertEqual(result, "こんにちは")
    }
    
    func testAPIErrorResponseThrowsError() async throws {
        try await keychain.saveKey("test_api_key", forService: mockKeyService)
        
        let errorJSON = """
        {
          "error": {
            "message": "Invalid API key provided."
          }
        }
        """
        let responseData = errorJSON.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }
        
        let engine = GeminiEngine(keychainService: keychain, session: session)
        
        do {
            _ = try await engine.refine(text: "Hello", prompt: "Translate to Japanese")
            XCTFail("Expected apiError")
        } catch let error as GeminiEngineError {
            XCTAssertEqual(error, .apiError(statusCode: 400, message: "Invalid API key provided."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testContentBlockedBySafetyFiltersThrowError() async throws {
        try await keychain.saveKey("test_api_key", forService: mockKeyService)
        
        let blockedJSON = """
        {
          "candidates": [
            {
              "content": {
                "parts": []
              },
              "finishReason": "SAFETY"
            }
          ]
        }
        """
        let responseData = blockedJSON.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }
        
        let engine = GeminiEngine(keychainService: keychain, session: session)
        
        do {
            _ = try await engine.refine(text: "Dangerous prompt", prompt: "Translate to Japanese")
            XCTFail("Expected contentBlocked error")
        } catch let error as GeminiEngineError {
            XCTAssertEqual(error, .contentBlocked)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

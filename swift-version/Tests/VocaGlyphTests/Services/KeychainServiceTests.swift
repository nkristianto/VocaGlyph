import XCTest
@testable import voice_to_text

final class KeychainServiceTests: XCTestCase {
    
    var keychainService: KeychainService!
    
    override func setUp() async throws {
        keychainService = KeychainService()
        // Ensure clean state before tests
        do {
            try await keychainService.deleteKey(forService: "com.vocaglyph.test.anthropic")
        } catch KeychainError.itemNotFound {
            // Expected if not present
        }
    }
    
    override func tearDown() async throws {
        // Clean up after tests
        do {
            try await keychainService.deleteKey(forService: "com.vocaglyph.test.anthropic")
        } catch KeychainError.itemNotFound {
            // Expected if not present
        }
        keychainService = nil
    }
    
    func testReadNonExistentKeyThrowsError() async {
        do {
            let _ = try await keychainService.readKey(forService: "com.vocaglyph.test.nonexistent")
            XCTFail("Expected itemNotFound error to be thrown")
        } catch KeychainError.itemNotFound {
            // Success
        } catch {
            XCTFail("Expected itemNotFound, got \(error)")
        }
    }
    
    func testSaveAndReadKey() async throws {
        let testKey = "test-sk-ant-api03-abcdefg-12345"
        let service = "com.vocaglyph.test.anthropic"
        
        // Save
        try await keychainService.saveKey(testKey, forService: service)
        
        // Read
        let retrievedKey = try await keychainService.readKey(forService: service)
        
        XCTAssertEqual(retrievedKey, testKey, "Retrieved key should match the saved key")
    }
    
    func testUpdateExistingKey() async throws {
        let originalKey = "original-key-123"
        let updatedKey = "updated-key-456"
        let service = "com.vocaglyph.test.anthropic"
        
        // Initial Save
        try await keychainService.saveKey(originalKey, forService: service)
        
        // Update
        try await keychainService.saveKey(updatedKey, forService: service)
        
        // Verify Update
        let retrievedKey = try await keychainService.readKey(forService: service)
        XCTAssertEqual(retrievedKey, updatedKey, "Retrieved key should be the updated key")
    }
    
    func testDeleteKey() async throws {
        let testKey = "key-to-delete-123"
        let service = "com.vocaglyph.test.anthropic"
        
        // Create and verify it exists
        try await keychainService.saveKey(testKey, forService: service)
        let _ = try await keychainService.readKey(forService: service)
        
        // Delete
        try await keychainService.deleteKey(forService: service)
        
        // Verify it's gone
        do {
            let _ = try await keychainService.readKey(forService: service)
            XCTFail("Expected itemNotFound error to be thrown after deletion")
        } catch KeychainError.itemNotFound {
            // Success
        } catch {
            XCTFail("Expected itemNotFound, got \(error)")
        }
    }
}

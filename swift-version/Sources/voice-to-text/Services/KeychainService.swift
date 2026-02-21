import Foundation
import Security

/// Errors that can occur during keychain operations.
public enum KeychainError: Error, Equatable {
    case itemNotFound
    case duplicateItem
    case invalidItemFormat
    case unhandledError(status: OSStatus)
}

/// A service for securely storing and retrieving credentials from the macOS Keychain.
/// Implemented as an actor to guarantee thread safety and main-thread isolation
/// for blocking `Security` framework operations.
public actor KeychainService {
    
    public init() {}
    
    /// Saves a string value to the keychain securely.
    ///
    /// - Parameters:
    ///   - key: The sensitive string data (e.g., API key) to store.
    ///   - service: A unique identifier for the service (e.g., "com.vocaglyph.anthropic").
    /// - Throws: `KeychainError` on failure.
    public func saveKey(_ key: String, forService service: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.invalidItemFormat
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Item exists, update it instead
            try updateKey(key, forService: service)
        } else if status != errSecSuccess {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Retrieves a string value from the keychain.
    ///
    /// - Parameter service: The unique identifier for the service.
    /// - Returns: The stored string.
    /// - Throws: `KeychainError` if not found or on other failures.
    public func readKey(forService service: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = item as? Data,
              let keyString = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidItemFormat
        }
        
        return keyString
    }
    
    /// Updates an existing keychain item. Internal helper.
    private func updateKey(_ key: String, forService service: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.invalidItemFormat
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Deletes a credential from the keychain.
    ///
    /// - Parameter service: The unique identifier for the service.
    /// - Throws: `KeychainError` if not found or on other failures.
    public func deleteKey(forService service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}

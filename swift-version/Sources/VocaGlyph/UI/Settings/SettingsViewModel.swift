import Foundation
import SwiftUI
import Combine

/// ViewModel for managing application settings, specifically handling secure credentials.
@MainActor
public final class SettingsViewModel: ObservableObject {
    
    @Published public var anthropicApiKey: String = ""
    @Published public var geminiApiKey: String = ""
    
    @Published public var isAnthropicKeySaved: Bool = false
    @Published public var isGeminiKeySaved: Bool = false
    
    @Published public var errorMessage: String?
    
    private let keychainService: KeychainService
    
    // Constants for Keychain service identifiers
    private let anthropicServiceId = "com.vocaglyph.api.anthropic"
    private let geminiServiceId = "com.vocaglyph.api.gemini"
    
    public init(keychainService: KeychainService = KeychainService()) {
        self.keychainService = keychainService
        
        Task {
            await loadKeys()
        }
    }
    
    /// Loads the obfuscated state of keys from the keychain.
    public func loadKeys() async {
        do {
            let _ = try await keychainService.readKey(forService: anthropicServiceId)
            self.isAnthropicKeySaved = true
            // We do not load the actual key into the text field for security
            self.anthropicApiKey = "" 
        } catch {
            self.isAnthropicKeySaved = false
        }
        
        do {
            let _ = try await keychainService.readKey(forService: geminiServiceId)
            self.isGeminiKeySaved = true
            self.geminiApiKey = ""
        } catch {
            self.isGeminiKeySaved = false
        }
    }
    
    /// Saves the Anthropic API Key securely.
    public func saveAnthropicKey() async {
        guard !anthropicApiKey.isEmpty else { return }
        errorMessage = nil
        do {
            try await keychainService.saveKey(anthropicApiKey, forService: anthropicServiceId)
            self.isAnthropicKeySaved = true
            self.anthropicApiKey = "" // Clear field after save
        } catch {
            self.errorMessage = "Failed to save Anthropic Key: \(error.localizedDescription)"
        }
    }
    
    /// Deletes the Anthropic API Key.
    public func deleteAnthropicKey() async {
        errorMessage = nil
        do {
            try await keychainService.deleteKey(forService: anthropicServiceId)
            self.isAnthropicKeySaved = false
            self.anthropicApiKey = ""
        } catch {
            self.errorMessage = "Failed to delete Anthropic Key: \(error.localizedDescription)"
        }
    }
    
    /// Saves the Gemini API Key securely.
    public func saveGeminiKey() async {
        guard !geminiApiKey.isEmpty else { return }
        errorMessage = nil
        do {
            try await keychainService.saveKey(geminiApiKey, forService: geminiServiceId)
            self.isGeminiKeySaved = true
            self.geminiApiKey = "" // Clear field after save
        } catch {
            self.errorMessage = "Failed to save Gemini Key: \(error.localizedDescription)"
        }
    }
    
    /// Deletes the Gemini API Key.
    public func deleteGeminiKey() async {
        errorMessage = nil
        do {
            try await keychainService.deleteKey(forService: geminiServiceId)
            self.isGeminiKeySaved = false
            self.geminiApiKey = ""
        } catch {
            self.errorMessage = "Failed to delete Gemini Key: \(error.localizedDescription)"
        }
    }
}

import Foundation
import AppKit

/// Apple Intelligence Post-Processing Engine
///
/// Uses macOS 15.1+ native AI frameworks (or bridging fallback) to refine text
/// locally and privately. Fails gracefully to raw text on unsupported software/hardware.
public actor AppleIntelligenceEngine: PostProcessingEngine {
    
    public init() {}
    
    public func refine(text: String, prompt: String) async throws -> String {
        guard #available(macOS 15.1, *) else {
            throw AppleIntelligenceError.unsupportedOSVersion
        }
        
        #if canImport(LanguageModel)
        // Future-proofing for when the native LanguageModel framework is publicly available
        throw AppleIntelligenceError.frameworkUnavailable
        #else
        // If an explicit framework isn't available, we would attempt bridging NSTextView Writing Tools
        // However, programmatically triggering Writing Tools without user UI interaction is currently unsupported
        // by the public AppKit APIs (it requires the user to select the text and invoke the panel).
        // Therefore, we throw to gracefully fallback to raw text.
        throw AppleIntelligenceError.programmaticAccessUnavailable
        #endif
    }
}

public enum AppleIntelligenceError: LocalizedError, Equatable {
    case unsupportedOSVersion
    case frameworkUnavailable
    case programmaticAccessUnavailable
    case inferenceFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedOSVersion:
            return "Apple Intelligence requires macOS 15.1 or later."
        case .frameworkUnavailable:
            return "The LanguageModel framework is not available."
        case .programmaticAccessUnavailable:
            return "Programmatic access to Apple Intelligence Writing Tools is currently unavailable."
        case .inferenceFailed(let reason):
            return "Apple Intelligence inference failed: \(reason)"
        }
    }
}

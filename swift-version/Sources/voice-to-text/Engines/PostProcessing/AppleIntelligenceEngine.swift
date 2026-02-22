import Foundation
import AppKit

/// Apple Intelligence Post-Processing Engine
///
/// Uses macOS 15.1+ native AI frameworks (or bridging fallback) to refine text
/// locally and privately. Fails gracefully to raw text on unsupported software/hardware.
public actor AppleIntelligenceEngine: PostProcessingEngine {
    
    public init() {}
    
    public func refine(text: String, prompt: String) async throws -> String {
        PostProcessingLogger.shared.info("AppleIntelligenceEngine: [REQUEST] Attempting refine — input=\(text.count) chars, prompt='\(prompt)'")

        guard #available(macOS 15.1, *) else {
            PostProcessingLogger.shared.error("AppleIntelligenceEngine: Failed — \(AppleIntelligenceError.unsupportedOSVersion.errorDescription ?? "")")
            throw AppleIntelligenceError.unsupportedOSVersion
        }
        
        #if canImport(LanguageModel)
        // Future-proofing for when the native LanguageModel framework is publicly available
        PostProcessingLogger.shared.error("AppleIntelligenceEngine: Failed — \(AppleIntelligenceError.frameworkUnavailable.errorDescription ?? "")")
        throw AppleIntelligenceError.frameworkUnavailable
        #else
        // Apple has not yet exposed a public programmatic API for Writing Tools / Apple Intelligence.
        // Programmatically triggering Writing Tools requires user UI interaction and is unsupported
        // by the current public AppKit APIs. We throw to gracefully fallback to raw text.
        PostProcessingLogger.shared.error("AppleIntelligenceEngine: Failed — \(AppleIntelligenceError.programmaticAccessUnavailable.errorDescription ?? "")")
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

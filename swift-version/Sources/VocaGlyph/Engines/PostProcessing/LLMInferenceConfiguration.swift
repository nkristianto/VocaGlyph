import Foundation

// MARK: - LLMInferenceConfiguration

/// Encapsulates all sampling parameters passed to the on-device Qwen LLM during inference.
///
/// These parameters are user-configurable via Settings and align with the MLX
/// `GenerateParameters` struct fields exposed by `mlx-swift-lm`.
///
/// ## Parameters Overview
///
/// - **temperature**: Controls output randomness. Lower = more deterministic/precise.
///   Range: 0.0–1.0. Default: 0.2 (good for transcription correction).
///
/// - **topP**: Nucleus sampling threshold. Restricts token selection to the smallest
///   set of candidates whose cumulative probability reaches this value.
///   Range: 0.0–1.0. Default: 0.9 (filters low-probability noise tokens).
///
/// - **repetitionPenalty**: Divides logit scores of previously-seen tokens to reduce
///   repetitive output. `nil` = disabled. Values > 1.0 penalize repetition.
///   Range: 1.0–1.3. Default: 1.1 (mild guard against repetition loops).
///
/// - **repetitionContextSize**: How many previous tokens to scan for repetitions.
///   Default: 64 (suitable for voice transcription sentence lengths).
public struct LLMInferenceConfiguration: Sendable {
    public let temperature: Float
    public let topP: Float
    public let repetitionPenalty: Float?
    public let repetitionContextSize: Int

    public init(
        temperature: Float,
        topP: Float,
        repetitionPenalty: Float? = nil,
        repetitionContextSize: Int = 64
    ) {
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.repetitionContextSize = repetitionContextSize
    }

    // MARK: - Presets

    /// Default configuration optimised for Qwen2.5-Instruct transcription correction.
    public static let `default` = LLMInferenceConfiguration(
        temperature: 0.0,
        topP: 1.0,
        repetitionPenalty: nil,
        repetitionContextSize: 64
    )

    /// Configuration following Qwen3 official recommendations for thinking-mode models.
    /// Greedy decoding (temperature=0) causes repetition loops in Qwen3 — min 0.4 required.
    public static let qwen3Default = LLMInferenceConfiguration(
        temperature: 0.6,
        topP: 0.95,
        repetitionPenalty: nil,
        repetitionContextSize: 64
    )

    // MARK: - UserDefaults Keys

    public static let temperatureKey = "llmTemperature"
    public static let topPKey = "llmTopP"
    public static let repetitionPenaltyKey = "llmRepetitionPenalty"

    // MARK: - Factory from UserDefaults

    /// Reads the three user-configurable parameters from `UserDefaults` and returns
    /// a configuration. Falls back to `.default` values if keys are absent.
    public static func fromUserDefaults() -> LLMInferenceConfiguration {
        let ud = UserDefaults.standard
        let temperature = ud.object(forKey: temperatureKey) != nil
            ? Float(ud.double(forKey: temperatureKey))
            : LLMInferenceConfiguration.default.temperature

        let topP = ud.object(forKey: topPKey) != nil
            ? Float(ud.double(forKey: topPKey))
            : LLMInferenceConfiguration.default.topP

        let rawPenalty = ud.object(forKey: repetitionPenaltyKey) != nil
            ? Float(ud.double(forKey: repetitionPenaltyKey))
            : (LLMInferenceConfiguration.default.repetitionPenalty ?? 1.0)

        // Treat penalty <= 1.0 as "disabled" (nil) so MLX skips the penalty pass entirely.
        let penaltyValue: Float? = rawPenalty > 1.0 ? rawPenalty : nil

        return LLMInferenceConfiguration(
            temperature: temperature,
            topP: topP,
            repetitionPenalty: penaltyValue,
            repetitionContextSize: 64
        )
    }
}

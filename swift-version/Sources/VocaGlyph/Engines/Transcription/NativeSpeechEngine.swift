import Foundation
import AVFoundation

#if canImport(Speech)
import Speech

@available(macOS 15.0, *)
public actor NativeSpeechEngine: TranscriptionEngine {

    // MARK: - Cached State
    //
    // Tier 1 optimisation: building an SFSpeechRecognizer and round-tripping
    // through the auth API on every transcribe() call adds ~30-80 ms overhead.
    // Cache both so they are created once per locale change.

    private var cachedRecognizer: SFSpeechRecognizer?
    private var cachedLocaleId: String?
    private var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    private var isAuthPrefetched = false

    // Fixed temp path – avoids UUID generation + directory stat on every call.
    private let tempFileURL: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("vocaglyph_native_audio")
        .appendingPathExtension("wav")

    // MARK: - Init

    public init() {
        Logger.shared.info("NativeSpeechEngine: Initialized")
    }

    // MARK: - Warm-up
    //
    // Call this when switching to the Apple engine so that auth is already
    // cached and the recognizer is eager-loaded before the first hotkey press.

    public func prepare() async {
        guard !isAuthPrefetched else { return }
        authStatus = await requestAuth()
        isAuthPrefetched = true
        Logger.shared.info("NativeSpeechEngine: Auth prefetched → \(authStatus.rawValue)")
        _ = recognizerForCurrentLocale()   // eager-create + cache
    }

    // MARK: - TranscriptionEngine

    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        Logger.shared.info("NativeSpeechEngine: Starting transcription (\(audioBuffer.frameLength) frames)")

        // ── Tier 2: macOS 26 SpeechAnalyzer ────────────────────────────────
        // SpeechAnalyzer (WWDC25) is fully on-device, has no 60-second limit,
        // supports "volatile" (fast/approximate) vs "final" results, and shares
        // its model with the OS so there is zero per-app warmup cost.
        //
        // We run this path when compiled with the macOS 26 SDK and fall back to
        // the SFSpeechRecognizer path on older OS versions.
        if #available(macOS 26.0, *) {
            do {
                return try await transcribeWithSpeechAnalyzer(audioBuffer: audioBuffer)
            } catch {
                // Any error (model unavailable, locale unsupported, etc.) falls
                // through to the proven SFSpeechRecognizer path below.
                Logger.shared.info("NativeSpeechEngine: SpeechAnalyzer path failed (\(error.localizedDescription)), falling back to SFSpeechRecognizer")
            }
        }

        // ── Tier 1: improved SFSpeechRecognizer ────────────────────────────
        return try await transcribeWithSFSpeechRecognizer(audioBuffer: audioBuffer)
    }

    // MARK: - Tier 2: SpeechAnalyzer (macOS 26+)
    //
    // The SpeechAnalyzer API was announced at WWDC25. It requires the Xcode 26
    // SDK to compile. The @available guard below ensures this function is only
    // called at runtime on macOS 26+ systems. If you are on an older Xcode/SDK,
    // the compiler will not attempt to resolve these symbols because the entire
    // function body is wrapped in @available(macOS 26.0, *).
    //
    // API shape per WWDC25 session "Elevate your app with Speech APIs":
    //   - SpeechTranscriber  – module that produces transcription results
    //   - SpeechAnalyzer     – coordinates modules and processes audio
    //   - Results come via an AsyncSequence with .volatile (fast) and .final tags

    @available(macOS 26.0, *)
    private func transcribeWithSpeechAnalyzer(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        #if swift(>=6.2)
        // SpeechAnalyzer + SpeechTranscriber were introduced in macOS 26 (WWDC25,
        // Xcode 26 SDK). This block is only compiled with Swift 6.2+ (Xcode 26+).
        // On earlier SDKs the block is excluded at compile time, so no missing-symbol
        // errors occur. The @available(macOS 26) guard ensures it never runs on older OS.
        let locale = Locale(identifier: localeIdentifierForCurrentLanguageSetting())
        let transcriber = SpeechTranscriber(locale: locale)
        let analyzer = try SpeechAnalyzer(modules: [transcriber])

        let audioFormat = audioBuffer.format
        try await analyzer.start(audioFormat: audioFormat)

        if let channelData = audioBuffer.floatChannelData {
            let frameCount = Int(audioBuffer.frameLength)
            if let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(frameCount)) {
                pcmBuffer.frameLength = audioBuffer.frameLength
                if let dst = pcmBuffer.floatChannelData?[0] {
                    dst.update(from: channelData[0], count: frameCount)
                }
                try await analyzer.analyzeAudio(pcmBuffer)
            }
        }

        await analyzer.stop()

        var volatileText = ""
        for await result in transcriber.transcriptionResults {
            switch result.stability {
            case .final:
                let text = result.segments.map { $0.substring }.joined(separator: " ")
                Logger.shared.info("NativeSpeechEngine: SpeechAnalyzer final result: '\(text)'")
                return text
            default:
                volatileText = result.segments.map { $0.substring }.joined(separator: " ")
            }
        }

        Logger.shared.info("NativeSpeechEngine: SpeechAnalyzer volatile result: '\(volatileText)'")
        return volatileText
        #else
        // Compiled without Xcode 26 SDK — signal unavailable so the caller falls
        // back to the SFSpeechRecognizer path.
        throw NSError(domain: "NativeSpeechEngine", code: 99,
                      userInfo: [NSLocalizedDescriptionKey: "SpeechAnalyzer requires Xcode 26 SDK."])
        #endif
    }

    // MARK: - Tier 1: improved SFSpeechRecognizer (macOS 15–25)

    private func transcribeWithSFSpeechRecognizer(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        // Auth – request once, cache thereafter (avoids the auth IPC on every call)
        if !isAuthPrefetched {
            authStatus = await requestAuth()
            isAuthPrefetched = true
        }

        guard authStatus == .authorized else {
            throw NSError(
                domain: "NativeSpeechEngine", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Apple Speech Recognition permission denied or restricted."]
            )
        }

        let recognizer = recognizerForCurrentLocale()

        guard recognizer.isAvailable else {
            throw NSError(
                domain: "NativeSpeechEngine", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Apple Dictation is temporarily unavailable on this device."]
            )
        }

        // Write to a fixed temp path instead of a new UUID file every call.
        do {
            if FileManager.default.fileExists(atPath: tempFileURL.path) {
                try FileManager.default.removeItem(at: tempFileURL)
            }
            let audioFile = try AVAudioFile(forWriting: tempFileURL, settings: audioBuffer.format.settings)
            try audioFile.write(from: audioBuffer)
        } catch {
            throw NSError(
                domain: "NativeSpeechEngine", code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write temp audio: \(error.localizedDescription)"]
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: tempFileURL)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false

        // taskHint = .dictation selects the recognizer's dictation-optimised
        // acoustic model — faster and more accurate for short voice input vs .unspecified.
        request.taskHint = .dictation

        // addsPunctuation offloads punctuation insertion to the recognizer (macOS 13+,
        // which is a strict subset of our macOS 15 minimum — always true).
        request.addsPunctuation = true

        Logger.shared.info("NativeSpeechEngine: Awaiting SFSpeechRecognizer result…")

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var bestStringSoFar = ""
            var recognitionTaskRef: SFSpeechRecognitionTask?

            recognitionTaskRef = recognizer.recognitionTask(with: request) { [self] result, error in
                if let error = error {
                    guard !hasResumed else { return }
                    hasResumed = true
                    try? FileManager.default.removeItem(at: tempFileURL)

                    let nsErr = error as NSError
                    let isSilence = error.localizedDescription.localizedCaseInsensitiveContains("No speech detected")
                        || nsErr.code == 201 || nsErr.code == 1110 || nsErr.code == 207
                    if isSilence {
                        continuation.resume(returning: bestStringSoFar)
                    } else {
                        Logger.shared.info("NativeSpeechEngine Error: \(error.localizedDescription)")
                        continuation.resume(returning: bestStringSoFar) // return partial rather than throw
                    }
                    return
                }

                if let result = result {
                    bestStringSoFar = result.bestTranscription.formattedString
                    Logger.shared.debug("NativeSpeechEngine: partial='\(bestStringSoFar)' isFinal=\(result.isFinal)")
                    if result.isFinal && !hasResumed {
                        hasResumed = true
                        try? FileManager.default.removeItem(at: self.tempFileURL)
                        Logger.shared.info("NativeSpeechEngine: Final result: '\(bestStringSoFar)'")
                        continuation.resume(returning: bestStringSoFar)
                    }
                }
            }

            // Safety timeout – cancel and return best partial result after 8 s.
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !hasResumed else { return }
                recognitionTaskRef?.cancel()
                hasResumed = true
                try? FileManager.default.removeItem(at: self.tempFileURL)
                Logger.shared.info("NativeSpeechEngine: Timeout – returning partial: '\(bestStringSoFar)'")
                continuation.resume(returning: bestStringSoFar)
            }
        }
    }

    // MARK: - Helpers

    /// Returns a cached `SFSpeechRecognizer` for the user's chosen locale,
    /// rebuilding it only when the locale setting changes.
    private func recognizerForCurrentLocale() -> SFSpeechRecognizer {
        let localeId = localeIdentifierForCurrentLanguageSetting()
        if let cached = cachedRecognizer, cachedLocaleId == localeId {
            return cached
        }
        // Fall back to en-US if the locale is unsupported (shouldn't happen, but safe).
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
        cachedRecognizer = recognizer
        cachedLocaleId = localeId
        Logger.shared.info("NativeSpeechEngine: Created recognizer for '\(localeId)'")
        return recognizer
    }

    private func requestAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func localeIdentifierForCurrentLanguageSetting() -> String {
        let savedLanguage = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "Auto-Detect"
        switch savedLanguage {
        case "English (US)":    return "en-US"
        case "Spanish (ES)":    return "es-ES"
        case "French (FR)":     return "fr-FR"
        case "German (DE)":     return "de-DE"
        case "Indonesian (ID)": return "id-ID"
        default:                return "en-US"   // Auto-Detect → SFSpeechRecognizer needs an explicit locale
        }
    }
}

// MARK: - Older SDK Fallback
#else

// Compiled without the Speech framework (shouldn't happen on macOS 15+).
public actor NativeSpeechEngine: TranscriptionEngine {
    public init() {}
    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        throw NSError(domain: "NativeSpeechEngine", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Speech framework unavailable on this OS."])
    }
}

#endif

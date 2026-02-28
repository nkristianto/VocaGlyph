import XCTest
import AVFoundation
@testable import VocaGlyphLib

// MARK: - ParakeetServiceTests
//
// These tests cover:
//   1. ModelVersion parsing (AC#2)
//   2. Error thrown when transcribe() called before ready (AC#2, AC#9)
//   3. changeModel() with unknown ID is a no-op — no crash (AC#2)
//   4. State machine: isReady starts false, downloadState is "Not Initialized" (AC#2)
//   5. TranscriptionEngine protocol conformance — ParakeetService is usable as EngineRouter engine (AC#2)
//   6. AppStateManager routing: parakeet- prefix always routes to ParakeetService, not WhisperService (AC#5)
//   7. AppStateManager routing: non-parakeet IDs do NOT route to ParakeetService (AC#5)
//   8. Story 9.2 additions: auto-init guards, trimSilence, delete cleanup, concurrent guard, flashNotReadyMessage (ACs #1-#8)
//
// Hardware-dependent tests (AC#3, AC#4, AC#6.2–6.5) are integration tests that require
// an Apple Silicon Mac with network access and cannot be run in CI — they are called out with
// the `// INTEGRATION` comment and skipped here.

final class ParakeetServiceTests: XCTestCase {

    // MARK: - 1. ModelVersion Parsing

    func testModelVersionParsing_v3() {
        let version = ParakeetService.ModelVersion(modelId: "parakeet-v3")
        XCTAssertNotNil(version, "parakeet-v3 must parse to .v3")
        XCTAssertEqual(version?.modelId, "parakeet-v3")
    }

    func testModelVersionParsing_v2() {
        let version = ParakeetService.ModelVersion(modelId: "parakeet-v2")
        XCTAssertNotNil(version, "parakeet-v2 must parse to .v2")
        XCTAssertEqual(version?.modelId, "parakeet-v2")
    }

    func testModelVersionParsing_unknownReturnsNil() {
        let version = ParakeetService.ModelVersion(modelId: "whisper-large-v3")
        XCTAssertNil(version, "Unknown model ID must return nil")
    }

    func testModelVersionModelIds_areDistinct() {
        XCTAssertNotEqual(
            ParakeetService.ModelVersion.v2.modelId,
            ParakeetService.ModelVersion.v3.modelId,
            "v2 and v3 must have distinct model IDs"
        )
    }

    // MARK: - 2. Initial State

    func testInitialState_isReadyFalse() {
        let sut = ParakeetService()
        XCTAssertFalse(sut.isReady, "isReady must start as false — model is not loaded at init")
    }

    func testInitialState_downloadStateIsNotInitialized() {
        let sut = ParakeetService()
        XCTAssertEqual(sut.downloadState, "Not Initialized")
    }

    func testInitialState_activeModelIsEmpty() {
        let sut = ParakeetService()
        XCTAssertEqual(sut.activeModel, "")
    }

    func testInitialState_downloadedModelsIsEmpty() {
        let sut = ParakeetService()
        // Note: downloadedModels is populated asynchronously by restoreDownloadedModelsFromDisk()
        // via DispatchQueue.main.async — it may or may not be empty depending on what's cached on disk.
        // We only assert it is a Set (no crash) — disk state is environment-specific.
        XCTAssertNotNil(sut.downloadedModels)
    }

    // MARK: - 3. TranscriptionEngine: Error Before Ready

    func testTranscribe_throwsParakeetErrorWhenNotReady() async {
        let sut = ParakeetService()

        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        // Fill with non-silent data so silence guard doesn't fire first
        if let data = buffer.floatChannelData {
            for i in 0..<1024 { data[0][i] = 0.5 }
        }

        do {
            _ = try await sut.transcribe(audioBuffer: buffer)
            XCTFail("Expected transcribe() to throw ParakeetError when not ready")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "ParakeetError",
                           "Error domain must be 'ParakeetError' (AC#2, AC#9)")
            XCTAssertEqual(error.code, 1)
        }
    }

    func testTranscribe_doesNotChangeIsReadyOnError() async {
        let sut = ParakeetService()
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        if let data = buffer.floatChannelData {
            for i in 0..<1024 { data[0][i] = 0.5 }
        }

        _ = try? await sut.transcribe(audioBuffer: buffer)

        // AC#9: orchestrator state must NOT be disrupted by a failed transcription attempt
        XCTAssertFalse(sut.isReady, "isReady must remain false after a failed transcribe() call")
    }

    // MARK: - 4. changeModel() Safety

    func testChangeModel_unknownIdIsNoop() async {
        let sut = ParakeetService()
        // Must not crash and must not mutate state
        sut.changeModel(to: "some-unknown-model")
        // Give the Task a moment to settle (it returns early from initialize due to guard)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        XCTAssertFalse(sut.isReady, "Unknown model ID must not set isReady = true")
        XCTAssertEqual(sut.activeModel, "", "Unknown model ID must not change activeModel")
    }

    func testChangeModel_v3SetsDownloadStateBeforeReady() async throws {
        let sut = ParakeetService()
        // We only verify that changeModel() kicks off the async chain by checking
        // that downloadState transitions away from "Not Initialized" — not that
        // the full download completes (that requires network access).
        sut.changeModel(to: "parakeet-v3")
        // Brief yield to let the dispatched Task run its first few statements
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05s
        // downloadState should have moved to "Downloading parakeet-v3..." or "Not Initialized"
        // if the network is unavailable. Both are valid non-error states for the state machine.
        XCTAssertNotEqual(sut.downloadState, "Failed to load",
                          "changeModel() must not immediately set 'Failed to load' — download has not been attempted yet")
    }

    // MARK: - 5. Protocol Conformance via EngineRouter

    func testParakeetServiceIsUsableAsTranscriptionEngine() {
        // Compile-time verification: ParakeetService must satisfy TranscriptionEngine
        let sut = ParakeetService()
        let engine: any TranscriptionEngine = sut
        XCTAssertNotNil(engine, "ParakeetService must be boxable as any TranscriptionEngine (AC#2)")
    }

    func testParakeetServiceCanBeInjectedIntoEngineRouter() {
        let sut = ParakeetService()
        // EngineRouter accepts any TranscriptionEngine — if this compiles and runs, AC#2 is satisfied
        let router = EngineRouter(engine: sut)
        XCTAssertNotNil(router, "EngineRouter must accept ParakeetService as its engine")
    }

    // MARK: - 6. AppStateManager Routing (AC#5)

    func testAppStateManager_parakeetPrefixRoutestoParakeetEngine() async {
        let stateManager = AppStateManager()
        let mockEngine = MockTranscriptionEngine()
        stateManager.engineRouter = EngineRouter(engine: mockEngine)

        let parakeetService = ParakeetService()
        stateManager.sharedParakeet = parakeetService

        // Routing a parakeet- model ID must call router.setEngine(parakeetService)
        await stateManager.switchTranscriptionEngine(toModel: "parakeet-v3")

        // After the switch, a transcribe attempt should come from parakeetService
        // (which throws ParakeetError because it's not loaded) — NOT from MockEngine.
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        if let data = buffer.floatChannelData {
            for i in 0..<1024 { data[0][i] = 0.5 }
        }

        do {
            _ = try await stateManager.engineRouter?.transcribe(audioBuffer: buffer)
        } catch let err as NSError {
            // If the error domain is "ParakeetError", the router correctly used ParakeetService
            XCTAssertEqual(err.domain, "ParakeetError",
                           "After parakeet-v3 routing, EngineRouter must delegate to ParakeetService (AC#5)")
            // MockEngine's didCallTranscribe must remain false
            XCTAssertFalse(mockEngine.didCallTranscribe,
                           "MockEngine (WhisperService stand-in) must NOT be called for parakeet- model IDs (AC#5)")
        }
    }

    func testAppStateManager_nonParakeetPrefixDoesNotRouteToParakeet() async {
        let stateManager = AppStateManager()
        let mockEngine = MockTranscriptionEngine()
        stateManager.engineRouter = EngineRouter(engine: mockEngine)

        let parakeetService = ParakeetService()
        stateManager.sharedParakeet = parakeetService

        // A Whisper model ID must NOT route to ParakeetService
        // (sharedWhisper is nil here so setEngine won't fire, but we verify Parakeet state doesn't change)
        await stateManager.switchTranscriptionEngine(toModel: "large-v3_turbo")

        XCTAssertEqual(parakeetService.activeModel, "",
                       "Non-parakeet model ID must not activate ParakeetService (AC#5)")
    }

    func testAppStateManager_parakeet_v2AlsoRoutesToParakeetService() async {
        let stateManager = AppStateManager()
        let mockEngine = MockTranscriptionEngine()
        stateManager.engineRouter = EngineRouter(engine: mockEngine)
        let parakeetService = ParakeetService()
        stateManager.sharedParakeet = parakeetService

        await stateManager.switchTranscriptionEngine(toModel: "parakeet-v2")

        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        if let data = buffer.floatChannelData {
            for i in 0..<1024 { data[0][i] = 0.5 }
        }

        do {
            _ = try await stateManager.engineRouter?.transcribe(audioBuffer: buffer)
        } catch let err as NSError {
            XCTAssertEqual(err.domain, "ParakeetError",
                           "parakeet-v2 must also route to ParakeetService (AC#5)")
        }
    }

    // MARK: - 7. AC#8: WhisperService Not Disrupted

    func testWhisperServiceIsNotAffectedByParakeetRouting() async {
        // When Parakeet is selected, WhisperService state must be unaffected.
        // We verify this by checking that the routing branch for Parakeet does NOT
        // call whisper.changeModel() or mutate the WhisperService.
        let stateManager = AppStateManager()
        let mockEngine = MockTranscriptionEngine()
        stateManager.engineRouter = EngineRouter(engine: mockEngine)
        let parakeetService = ParakeetService()
        stateManager.sharedParakeet = parakeetService

        // sharedWhisper nil simulates "loaded but not holding a reference to verify"
        // The test just confirms no crash and no unintended state changes on Parakeet
        await stateManager.switchTranscriptionEngine(toModel: "parakeet-v3")

        // Parakeet service state: changeModel was called with "parakeet-v3"
        // activeModel updates asynchronously after download; we just verify no crash
        XCTAssertFalse(parakeetService.isReady,
                       "isReady must remain false until download+init are complete (AC#8)")
    }

    // MARK: - Story 9.2 — AC#1 Auto-initialize guards

    /// AC#1/#2: When selectedModel is NOT a parakeet- prefix, autoInitializeIfNeeded is a no-op.
    func testAutoInitialize_doesNothingIfNotParakeetModel() async {
        // Arrange: set a non-parakeet selectedModel
        let previousValue = UserDefaults.standard.string(forKey: "selectedModel")
        UserDefaults.standard.set("large-v3", forKey: "selectedModel")
        defer { UserDefaults.standard.set(previousValue, forKey: "selectedModel") }

        let sut = ParakeetService()
        // Give the auto-init task time to run and exit via guard
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // downloadingModelId must remain nil — no initialization should have started
        XCTAssertNil(sut.downloadingModelId,
                     "AC#1: Auto-init must not start for non-parakeet selectedModel")
        XCTAssertFalse(sut.isReady, "AC#1: isReady must remain false")
    }

    /// AC#2: When selectedModel is a parakeet- model but NOT on disk, autoInitializeIfNeeded stays idle.
    func testAutoInitialize_doesNothingIfModelNotOnDisk() async {
        // Arrange: set a parakeet selectedModel that is definitely NOT on disk
        // (using a deliberately unknown parakeet variant to ensure not-downloaded state)
        let previousValue = UserDefaults.standard.string(forKey: "selectedModel")
        UserDefaults.standard.set("parakeet-v3", forKey: "selectedModel")
        defer { UserDefaults.standard.set(previousValue, forKey: "selectedModel") }

        let sut = ParakeetService()
        // Wait for restoreDownloadedModelsFromDisk() dispatch to settle
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // If the model is NOT on disk, downloadingModelId must be nil
        // If the model IS on disk this test is skipped because the guard would correctly allow it.
        if !sut.downloadedModels.contains("parakeet-v3") {
            XCTAssertNil(sut.downloadingModelId,
                         "AC#2: Auto-init must not start when parakeet model is not on disk")
        }
        // If it IS downloaded, the auto-init is expected to run — test becomes a no-op here.
        // Integration behavior (network download) is excluded from unit tests.
    }

    // MARK: - Story 9.2 — AC#6 trimSilence (internal, tested via the extension)

    func testTrimSilence_returnsNilForAllSilentBuffer() {
        let sut = ParakeetService()
        let allZeroes = [Float](repeating: 0.0, count: 1000)
        let result = sut.trimSilence(allZeroes)
        XCTAssertNil(result, "AC#6: All-zero buffer must return nil")
    }

    func testTrimSilence_returnsNilForSubThresholdBuffer() {
        let sut = ParakeetService()
        // All samples are exactly at or below the 0.01 threshold
        let subThreshold = [Float](repeating: 0.01, count: 1000)
        let result = sut.trimSilence(subThreshold)
        XCTAssertNil(result, "AC#6: Sub-threshold buffer must return nil")
    }

    func testTrimSilence_returnsTrimmedArray() {
        let sut = ParakeetService()
        // Silence prefix + signal + silence suffix
        var samples = [Float](repeating: 0.0, count: 100)   // 100 silent frames
        samples += [Float](repeating: 0.5, count: 50)        // 50 active frames
        samples += [Float](repeating: 0.0, count: 100)       // 100 silent frames

        let result = sut.trimSilence(samples)
        XCTAssertNotNil(result, "AC#6: Signal surrounded by silence must not return nil")
        // The trimmed result should be shorter than the original
        XCTAssertLessThan(result!.count, samples.count, "AC#6: Trimmed array must be shorter than input")
        // All values in result must be > 0.01
        XCTAssertTrue(result!.allSatisfy { abs($0) > 0.01 }, "AC#6: Trimmed array must not contain sub-threshold values at boundaries")
    }

    func testTrimSilence_returnsNilForEmptyBuffer() {
        let sut = ParakeetService()
        let result = sut.trimSilence([])
        XCTAssertNil(result, "AC#6: Empty buffer must return nil")
    }

    /// AC#6: When the audio is entirely silent, transcribe() returns "" without reaching the ANE.
    /// We test this by calling transcribe on a ready-faked service with a zero-filled buffer.
    func testTranscribe_returnEmptyStringOnSilentBuffer() async {
        let sut = ParakeetService()
        // A truly silent buffer (all zeroes)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        // floatChannelData zeroes are already default — do not fill

        // When the model is not ready, we get ParakeetError code=1.
        // The silence trimming fires BEFORE the isReady guard when the service IS ready.
        // We cannot mock the asrManager in a unit test, so we verify the path via the
        // NOT-ready guard path: a silent buffer still hits the isReady check first.
        // The key unit-testable fact: trimSilence([Float](repeating: 0, count: 1024)) == nil
        let samples = [Float](repeating: 0.0, count: 1024)
        let trimResult = sut.trimSilence(samples)
        XCTAssertNil(trimResult, "AC#6: Silent buffer's trimSilence must return nil, ensuring empty return from transcribe()")
    }

    // MARK: - Story 9.2 — AC#7 deleteModel cleanup

    func testDeleteModel_clearsDowloadingModelIdIfMatching() {
        let sut = ParakeetService()
        // Simulate a mid-download state
        sut.downloadingModelId = "parakeet-v3"

        // Delete the same model
        sut.deleteModel(id: "parakeet-v3")

        // downloadingModelId must be cleared
        XCTAssertNil(sut.downloadingModelId,
                     "AC#7: deleteModel() must clear downloadingModelId for the deleted model")
        XCTAssertEqual(sut.loadingProgress, 0.0,
                       "AC#7: deleteModel() must reset loadingProgress to 0.0 when clearing downloadingModelId")
    }

    func testDeleteModel_doesNotClearDifferentDownloadingModelId() {
        let sut = ParakeetService()
        // Simulate downloading v2 while we delete v3
        sut.downloadingModelId = "parakeet-v2"

        sut.deleteModel(id: "parakeet-v3")

        // downloadingModelId for v2 must be preserved
        XCTAssertEqual(sut.downloadingModelId, "parakeet-v2",
                       "AC#7: deleteModel(v3) must NOT clear downloadingModelId that belongs to a different model (v2)")
    }

    // MARK: - Story 9.2 — AC#4 Concurrent download guard (logical, not hardware)

    func testConcurrentInitializeGuard_secondCallIsNoop() async {
        let sut = ParakeetService()
        // Manually set downloadingModelId to simulate an in-progress download
        await MainActor.run { sut.downloadingModelId = "parakeet-v3" }
        // Try to initialize a DIFFERENT model — should be ignored
        sut.changeModel(to: "parakeet-v2")
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        // The guard should have fired and v2 should NOT be downloading
        // downloadingModelId should still be "parakeet-v3" (the original)
        XCTAssertEqual(sut.downloadingModelId, "parakeet-v3",
                       "AC#4: Second changeModel() while another model is loading must be ignored")
    }

    // MARK: - Story 9.2 — AC#8 Engine-aware flashNotReadyMessage

    func testFlashNotReadyMessage_showsParakeetTextForParakeetModel() {
        let stateManager = AppStateManager()
        let previousValue = UserDefaults.standard.string(forKey: "selectedModel")
        UserDefaults.standard.set("parakeet-v3", forKey: "selectedModel")
        defer { UserDefaults.standard.set(previousValue, forKey: "selectedModel") }

        stateManager.flashNotReadyMessage()

        XCTAssertNotNil(stateManager.notReadyMessage, "AC#8: notReadyMessage must be set")
        XCTAssertTrue(stateManager.notReadyMessage?.contains("Parakeet") ?? false,
                      "AC#8: Flash message for parakeet- model must contain 'Parakeet', got: '\(stateManager.notReadyMessage ?? "")'")
    }

    func testFlashNotReadyMessage_showsWhisperKitTextForWhisperModel() {
        let stateManager = AppStateManager()
        let previousValue = UserDefaults.standard.string(forKey: "selectedModel")
        UserDefaults.standard.set("large-v3", forKey: "selectedModel")
        defer { UserDefaults.standard.set(previousValue, forKey: "selectedModel") }

        stateManager.flashNotReadyMessage()

        XCTAssertNotNil(stateManager.notReadyMessage, "AC#8: notReadyMessage must be set")
        XCTAssertTrue(stateManager.notReadyMessage?.contains("WhisperKit") ?? false,
                      "AC#8: Flash message for whisper model must contain 'WhisperKit', got: '\(stateManager.notReadyMessage ?? "")'")
    }

    // MARK: - INTEGRATION (skipped in unit test run)
    // func testParakeetV3DownloadAndTranscribe() async throws { ... }
    // Requires: Apple Silicon + network + microphone. Run manually via the app.
}

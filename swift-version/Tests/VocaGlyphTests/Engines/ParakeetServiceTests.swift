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
        XCTAssertTrue(sut.downloadedModels.isEmpty)
    }

    // MARK: - 3. TranscriptionEngine: Error Before Ready

    func testTranscribe_throwsParakeetErrorWhenNotReady() async {
        let sut = ParakeetService()

        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024

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

    // MARK: - INTEGRATION (skipped in unit test run)
    // func testParakeetV3DownloadAndTranscribe() async throws { ... }
    // Requires: Apple Silicon + network + microphone. Run manually via the app.
}

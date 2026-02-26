import XCTest
@testable import VocaGlyph

// MARK: - LaunchAtLoginManagerTests

final class LaunchAtLoginManagerTests: XCTestCase {

    // MARK: - Initial State

    func test_initialState_reflectsSystemServiceStatus() async throws {
        // LaunchAtLoginManager reads SMAppService.mainApp.status at init time.
        // We can't control the system service in unit tests, so just assert the
        // property is readable and doesn't crash.
        let manager = await LaunchAtLoginManager()
        let _ = await manager.isEnabled
        XCTAssertTrue(true, "initialising LaunchAtLoginManager should not crash")
    }

    // MARK: - setEnabled

    func test_setEnabled_true_attemptsRegistration() async throws {
        // This test verifies the happy-path flow does not throw for the app.
        // On a simulator / CI where SMAppService is unavailable, the do-catch
        // will catch the error and revert isEnabled to false — this is the
        // expected safe behaviour.
        let manager = await LaunchAtLoginManager()
        // Attempt — either succeeds or gracefully reverts. Must not crash.
        await manager.setEnabled(true)
        // After the call, isEnabled should equal the actual service status.
        let actual = SMAppService.mainApp.status == .enabled
        let managed = await manager.isEnabled
        XCTAssertEqual(managed, actual)
    }

    func test_setEnabled_false_attemptsUnregistration() async throws {
        let manager = await LaunchAtLoginManager()
        await manager.setEnabled(false)
        // On a real machine this may succeed or fail; either way isEnabled must
        // reflect the *real* service status.
        let actual = SMAppService.mainApp.status == .enabled
        let managed = await manager.isEnabled
        XCTAssertEqual(managed, actual)
    }

    func test_setEnabled_toggle_doesNotCrash() async throws {
        let manager = await LaunchAtLoginManager()
        let initial = await manager.isEnabled
        // Toggle on → off (or off → on) twice — should never crash
        await manager.setEnabled(!initial)
        await manager.setEnabled(initial)
        XCTAssertTrue(true, "double-toggle must not crash")
    }
}

// MARK: - ShortcutRecorderButton State (no NSEvent monitor in unit tests)

/// ShortcutRecorderButton logic is AppKit-event-loop-coupled (NSEvent monitor),
/// so it is covered by dedicated manual UI tests rather than unit tests.
/// This placeholder documents that decision.
final class ShortcutRecorderButtonTests: XCTestCase {
    func test_placeholder_documentedAsManualTest() {
        XCTAssertTrue(true, "ShortcutRecorderButton requires manual UI testing via the Settings window.")
    }
}

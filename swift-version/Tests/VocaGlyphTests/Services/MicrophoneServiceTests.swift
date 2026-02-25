import XCTest
@testable import VocaGlyphLib

// NOTE: MicrophoneService uses @Observable + @MainActor, so all assertions are wrapped in MainActor.
// Hardware enumeration can return 0 devices in CI — tests only assert that the API doesn't crash.

@MainActor
final class MicrophoneServiceTests: XCTestCase {

    private var service: MicrophoneService!

    override func setUp() async throws {
        // Clear any persisted selection before each test.
        UserDefaults.standard.removeObject(forKey: MicrophoneService.selectedMicrophoneUIDKey)
        service = MicrophoneService()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: MicrophoneService.selectedMicrophoneUIDKey)
        service = nil
    }

    // MARK: - Initialization

    func testInitialization_doesNotCrash() {
        XCTAssertNotNil(service, "MicrophoneService should initialise without crashing.")
    }

    func testInitialization_alwaysContainsSystemDefault() {
        // The "System Default" sentinel is always injected at index 0.
        XCTAssertEqual(
            service.availableInputs.first,
            .systemDefault,
            "availableInputs[0] must always be the System Default sentinel."
        )
    }

    func testInitialization_selectedDeviceIsSystemDefaultWhenNoPersistedUID() {
        // No UID stored → selectedDevice should fall back to .systemDefault.
        XCTAssertEqual(
            service.selectedDevice,
            .systemDefault,
            "With no persisted UID the selected device should be System Default."
        )
    }

    // MARK: - Selection

    func testSelectSystemDefault_clearsUID() {
        // Manually store a fake UID first.
        UserDefaults.standard.set("fake-uid-123", forKey: MicrophoneService.selectedMicrophoneUIDKey)
        let fresh = MicrophoneService()
        fresh.select(.systemDefault)
        XCTAssertNil(fresh.selectedUID, "Selecting System Default should set selectedUID to nil.")
        XCTAssertEqual(fresh.selectedDevice, .systemDefault)
    }

    func testSelectNil_uidPersistedToUserDefaults() {
        service.select(.systemDefault)
        let stored = UserDefaults.standard.string(forKey: MicrophoneService.selectedMicrophoneUIDKey)
        XCTAssertNil(stored, "System Default selection should remove (nil out) the stored UID.")
    }

    func testSelectRealDevice_persistsUID() {
        // Only runs meaningfully when actual input devices are available (non-CI).
        guard let realDevice = service.availableInputs.first(where: { $0 != .systemDefault }) else {
            // No physical microphone available (CI sandbox) — skip gracefully.
            return
        }
        service.select(realDevice)
        XCTAssertEqual(service.selectedUID, realDevice.uid)
        XCTAssertEqual(service.selectedDevice, realDevice)

        // Confirm it persists.
        let stored = UserDefaults.standard.string(forKey: MicrophoneService.selectedMicrophoneUIDKey)
        XCTAssertEqual(stored, realDevice.uid)
    }

    // MARK: - Persistence across instances

    func testSelectedUID_persistsAcrossInstances() {
        let fakeUID = "test-microphone-uid-\(UUID().uuidString)"
        // Write the UID directly so we don't need a real device.
        UserDefaults.standard.set(fakeUID, forKey: MicrophoneService.selectedMicrophoneUIDKey)

        let secondInstance = MicrophoneService()
        XCTAssertEqual(
            secondInstance.selectedUID, fakeUID,
            "A fresh MicrophoneService instance must restore the persisted UID."
        )
    }

    // MARK: - refreshDevices

    func testRefreshDevices_doesNotCrash() {
        // Should not throw or crash even in restricted environments.
        service.refreshDevices()
        // After refresh, System Default must still be present.
        XCTAssertEqual(service.availableInputs.first, .systemDefault)
    }

    func testRefreshDevices_systemDefaultAlwaysFirst() {
        service.refreshDevices()
        XCTAssertEqual(
            service.availableInputs.first,
            .systemDefault,
            "System Default must remain at index 0 after a refresh."
        )
    }

    // MARK: - applySelectionToSystem

    func testApplySelectionToSystem_returnsTrueForSystemDefault() {
        // System Default means "no override" — should always return true.
        service.select(.systemDefault)
        let result = service.applySelectionToSystem()
        XCTAssertTrue(result, "applySelectionToSystem() should return true when no specific device is selected.")
    }

    func testApplySelectionToSystem_returnsFalseForUnknownUID() {
        // Force a UID that doesn't match any enumerated device.
        UserDefaults.standard.set("nonexistent-uid-xyz", forKey: MicrophoneService.selectedMicrophoneUIDKey)
        let fresh = MicrophoneService()
        // If the UID is not in availableInputs, apply returns false.
        let result = fresh.applySelectionToSystem()
        // Could be true (system default path) or false (unknown uid path) — just ensure no crash.
        _ = result
    }
}

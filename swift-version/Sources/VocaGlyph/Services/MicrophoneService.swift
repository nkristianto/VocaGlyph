import AVFoundation
import CoreAudio
import Foundation
import Observation

// MARK: - MicrophoneDevice

/// A value-type snapshot of an audio input device, safe to pass across threads and store in UserDefaults.
struct MicrophoneDevice: Identifiable, Equatable {
    /// CoreAudio device identifier — stable for the lifetime of a hardware connection.
    let id: AudioDeviceID
    /// Human-readable name shown in the UI.
    let name: String
    /// Unique String identifier, used for persistence.
    let uid: String

    static let systemDefault = MicrophoneDevice(id: kAudioObjectUnknown, name: "System Default", uid: "")
}

// MARK: - MicrophoneService

/// Manages enumeration and selection of audio input devices for the app.
///
/// - Enumerates devices via CoreAudio (`kAudioHardwarePropertyDevices`).
/// - Persists the selected device UID in `UserDefaults`.
/// - Applies the selection by setting the macOS system-default input device
///   via `AudioObjectSetPropertyData` before each recording session.
/// - Refreshes the device list when hardware is connected/disconnected.
@Observable
@MainActor
final class MicrophoneService {

    // MARK: - UserDefaults key

    static let selectedMicrophoneUIDKey = "selectedMicrophoneUID"

    // MARK: - Published state

    /// All currently available audio input devices, including the system-default sentinel.
    private(set) var availableInputs: [MicrophoneDevice] = []

    /// UID of the currently selected device, or `""` / `nil` for system default.
    private(set) var selectedUID: String? {
        didSet {
            UserDefaults.standard.set(selectedUID, forKey: Self.selectedMicrophoneUIDKey)
        }
    }

    /// Convenience: the `MicrophoneDevice` matching `selectedUID`, or `.systemDefault`.
    var selectedDevice: MicrophoneDevice {
        guard let uid = selectedUID, !uid.isEmpty else { return .systemDefault }
        return availableInputs.first { $0.uid == uid } ?? .systemDefault
    }

    // MARK: - Lifecycle

    init() {
        // Restore persisted selection
        selectedUID = UserDefaults.standard.string(forKey: Self.selectedMicrophoneUIDKey)
        refreshDevices()
        registerHardwareListeners()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Re-enumerates all audio input devices and updates `availableInputs`.
    func refreshDevices() {
        let devices = enumerateInputDevices()
        availableInputs = [.systemDefault] + devices
        Logger.shared.info("MicrophoneService: Found \(devices.count) input device(s).")
    }

    /// Sets `device` as the preferred input. Pass `.systemDefault` to clear the override.
    func select(_ device: MicrophoneDevice) {
        if device == .systemDefault {
            selectedUID = nil
            Logger.shared.info("MicrophoneService: Selected system default microphone.")
        } else {
            selectedUID = device.uid
            Logger.shared.info("MicrophoneService: Selected '\(device.name)' (uid=\(device.uid)).")
        }
    }

    /// Applies the currently selected device as the CoreAudio system default input.
    /// Call this just before starting a recording session so `AVAudioEngine.inputNode`
    /// picks up the chosen device.
    ///
    /// `nonisolated` so it can be called safely from the audio queue (background thread)
    /// in `AudioRecorderService.startRecording()`. The underlying CoreAudio C APIs are
    /// not actor-bound and are safe to call from any thread.
    ///
    /// Returns `true` if the device was found and the system call succeeded, `false` otherwise.
    @discardableResult
    nonisolated func applySelectionToSystem() -> Bool {
        // Read the persisted UID directly from UserDefaults — safe from any thread.
        guard let uid = UserDefaults.standard.string(forKey: Self.selectedMicrophoneUIDKey),
              !uid.isEmpty else {
            // No override — let the OS use whatever the user has set system-wide.
            return true
        }
        // Find the AudioDeviceID for the stored UID via CoreAudio.
        guard let deviceID = findDeviceID(for: uid) else {
            Logger.shared.info("MicrophoneService: Preferred device '\(uid)' not found; using system default.")
            return false
        }
        return setSystemDefaultInput(deviceID: deviceID)
    }

    // MARK: - CoreAudio helpers

    private func enumerateInputDevices() -> [MicrophoneDevice] {
        // 1. Get all AudioDeviceID values from the system object.
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        // 2. Filter to input-capable devices only, then build MicrophoneDevice values.
        return deviceIDs.compactMap { deviceID -> MicrophoneDevice? in
            guard hasInputStreams(deviceID: deviceID) else { return nil }
            guard let name = deviceName(deviceID: deviceID),
                  let uid  = deviceUID(deviceID: deviceID) else { return nil }
            return MicrophoneDevice(id: deviceID, name: name, uid: uid)
        }
    }

    /// Returns `true` when the device has at least one input stream.
    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        // Allocate an AudioBufferList with exactly `dataSize` bytes
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }

        var mutableAddress = address
        var mutableSize = dataSize
        let getStatus = AudioObjectGetPropertyData(deviceID, &mutableAddress, 0, nil, &mutableSize, rawPtr)
        guard getStatus == noErr else { return false }

        let bufferList = rawPtr.load(as: AudioBufferList.self)
        return bufferList.mNumberBuffers > 0
    }

    /// Finds the AudioDeviceID for a given UID string by enumerating all devices.
    /// `nonisolated` and safe to call from any thread.
    private nonisolated func findDeviceID(for uid: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return nil }

        return deviceIDs.first { deviceUID(deviceID: $0) == uid }
    }

    private nonisolated func deviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &ref)
        guard status == noErr, let cfRef = ref else { return nil }
        return cfRef.takeRetainedValue() as String
    }

    private nonisolated func deviceUID(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &ref)
        guard status == noErr, let cfRef = ref else { return nil }
        return cfRef.takeRetainedValue() as String
    }

    /// Sets the macOS system-wide default audio input device.
    @discardableResult
    private nonisolated func setSystemDefaultInput(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            dataSize,
            &mutableDeviceID
        )
        if status == noErr {
            Logger.shared.info("MicrophoneService: System default input set to deviceID=\(deviceID).")
        } else {
            Logger.shared.error("MicrophoneService: Failed to set system default input (OSStatus=\(status)).")
        }
        return status == noErr
    }

    // MARK: - Hardware change notifications

    private func registerHardwareListeners() {
        // AVCaptureDevice notifications fire on macOS when devices are added/removed.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnected),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceDisconnected),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    @objc private func handleDeviceConnected(_ notification: Notification) {
        Task { @MainActor in
            Logger.shared.info("MicrophoneService: Audio device connected — refreshing list.")
            self.refreshDevices()
        }
    }

    @objc private func handleDeviceDisconnected(_ notification: Notification) {
        Task { @MainActor in
            Logger.shared.info("MicrophoneService: Audio device disconnected — refreshing list.")
            self.refreshDevices()
            // If the disconnected device was selected, fall back to system default.
            if let uid = self.selectedUID, !uid.isEmpty {
                let stillAvailable = self.availableInputs.contains { $0.uid == uid }
                if !stillAvailable {
                    Logger.shared.info("MicrophoneService: Selected device disappeared — reverting to system default.")
                    self.selectedUID = nil
                }
            }
        }
    }
}

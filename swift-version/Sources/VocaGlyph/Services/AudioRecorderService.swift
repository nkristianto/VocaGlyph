import AVFoundation
import Foundation

// MARK: - Config Change Delegate

/// Notified when `AVAudioEngine` must be rebuilt (e.g. after a TCC permission grant
/// or a hardware reconfiguration triggered by a window focus change).
protocol AudioRecorderConfigChangeDelegate: AnyObject {
    func audioRecorderDidLoseConfiguration(_ recorder: AudioRecorderService)
}

class AudioRecorderService {
    private let engine = AVAudioEngine()

    // The target format required by WhisperKit: 16kHz, 1 channel (mono), 32-bit Float
    private let targetSampleRate: Double = 16000.0
    private var converter: AVAudioConverter?

    // Thread-safe buffer: appended from the audio tap thread, read on any thread.
    // Using a dedicated serial queue + NSLock ensures stopRecording() drains
    // cleanly even when pending tap callbacks are still in-flight.
    private var recordedData: [Float] = []
    private let bufferLock = NSLock()
    private let bufferQueue = DispatchQueue(label: "com.vocaglyph.audioBuffer", qos: .userInteractive)

    /// Notified when the engine's hardware configuration changes (e.g. after mic permission
    /// is granted or the Settings window triggers an audio graph reconfiguration).
    weak var configChangeDelegate: AudioRecorderConfigChangeDelegate?

    init() {
        requestPermissions()
        // Watch for AVAudioEngine I/O reconfigurations (device changes, window focus
        // transitions, post-TCC permission grants). Without this the engine can become
        // silently broken and the next startRecording() captures no audio.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        // macOS delivers this notification when the I/O unit is interrupted (e.g. device
        // change, audio route reconfiguration). The OS has already stopped the engine before
        // sending it — do NOT call engine.stop() or removeTap() here; they can deadlock with
        // the audio render thread in some configurations.
        // startRecording() already tears down and rebuilds the engine graph on every call,
        // so the next hotkey press will recover automatically.
        Logger.shared.info("AudioRecorder: AVAudioEngine configuration changed — notifying delegate.")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.configChangeDelegate?.audioRecorderDidLoseConfiguration(self)
        }
    }

    private func requestPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            Logger.shared.info("Microphone access ready.")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Logger.shared.info("Microphone access granted: \(granted)")
            }
        default:
            Logger.shared.info("Microphone access denied or restricted.")
        }
    }

    // MARK: - startRecording
    // Throws if the audio engine cannot be started so that callers can
    // immediately reset state rather than silently hanging.
    func startRecording() throws {
        // 1. Reset accumulated data
        bufferLock.lock()
        recordedData.removeAll()
        bufferLock.unlock()

        // 2. Tear down any previous session completely before reconfiguring.
        //    Always remove an existing tap first — re-installing without removing
        //    causes a silent failure that leaves no audio captured.
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // 3. Build the target 16 kHz mono format
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.formatCreationFailed
        }

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        Logger.shared.info("AudioRecorder: Starting — input format: \(inputFormat)")

        // 4. Install tap. The tap callback is called on a private audio thread;
        //    we hand the work to our serial bufferQueue to avoid blocking it.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.bufferQueue.async { self?.processBuffer(buffer: buffer) }
        }

        // 5. Start engine — throw on failure so callers know immediately.
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Clean up the tap we just installed so the next attempt starts fresh.
            engine.inputNode.removeTap(onBus: 0)
            Logger.shared.error("AudioRecorder: Failed to start engine — \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - stopRecording
    // Stops the engine + tap, then waits for any in-flight buffer appends to
    // finish (by synchronously draining bufferQueue) before assembling the
    // final PCM buffer.
    func stopRecording() -> AVAudioPCMBuffer? {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        // Drain any pending buffer appends that were dispatched before we
        // removed the tap.  sync{} blocks until the queue is empty.
        bufferQueue.sync {}

        bufferLock.lock()
        let data = recordedData
        recordedData.removeAll()
        bufferLock.unlock()

        Logger.shared.info("AudioRecorder: Stopped — captured \(data.count) frames at 16 kHz")

        guard !data.isEmpty else { return nil }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count)) else {
            return nil
        }

        buffer.frameLength = buffer.frameCapacity
        if let channelData = buffer.floatChannelData {
            data.withUnsafeBufferPointer { src in
                channelData[0].update(from: src.baseAddress!, count: data.count)
            }
        }

        return buffer
    }

    // MARK: - Private helpers

    private func processBuffer(buffer: AVAudioPCMBuffer) {
        // Fast path: already in the right format
        if buffer.format.sampleRate == targetSampleRate && buffer.format.channelCount == 1 {
            appendBufferData(buffer)
            return
        }
        guard let converter = self.converter else { return }
        let targetFormat = converter.outputFormat

        let capacity = AVAudioFrameCount(
            Double(buffer.frameCapacity) * (targetFormat.sampleRate / buffer.format.sampleRate)
        )
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var hasProvidedData = false
        var conversionError: NSError?

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasProvidedData {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedData = true
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: targetBuffer, error: &conversionError, withInputFrom: inputBlock)
        guard status != .error, conversionError == nil else {
            Logger.shared.error("AudioRecorder: Buffer conversion failed — \(conversionError?.localizedDescription ?? "unknown")")
            return
        }

        appendBufferData(targetBuffer)
    }

    // Called exclusively from bufferQueue — lock guards against concurrent
    // access with stopRecording() which reads on the calling thread.
    private func appendBufferData(_ buffer: AVAudioPCMBuffer) {
        guard let floatChannelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let slice = Array(UnsafeBufferPointer(start: floatChannelData[0], count: frameLength))

        bufferLock.lock()
        recordedData.append(contentsOf: slice)
        bufferLock.unlock()
    }
}

// MARK: - Errors
enum AudioRecorderError: Error, LocalizedError {
    case formatCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: return "Could not create 16 kHz output format"
        }
    }
}

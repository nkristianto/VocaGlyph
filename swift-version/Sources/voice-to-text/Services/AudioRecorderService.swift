import AVFoundation
import Foundation

class AudioRecorderService {
    private let engine = AVAudioEngine()
    
    // The target format required by WhisperKit: 16Khz, 1 channel (mono), 32-bit Float
    private let targetSampleRate: Double = 16000.0
    private var converter: AVAudioConverter?
    
    // Memory buffer to hold incoming audio data
    private var recordedData: [Float] = []
    
    init() {
        requestPermissions()
    }
    
    private func requestPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("Microphone access ready.")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("Microphone access granted: \(granted)")
            }
        default:
            print("Microphone access denied or restricted.")
        }
    }
    
    func startRecording() {
        recordedData.removeAll()
        
        // Ensure engine is stopped before configuring
        if engine.isRunning {
            engine.stop()
        }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Define the target format: 16kHz, 1 channel, 32-bit Float, non-interleaved
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("Error: Could not create 16kHz output format.")
            return
        }
        
        // Create an audio converter
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        
        print("Starting recording... Input format: \(inputFormat)")
        
        // Install a tap on the input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            self.processBuffer(buffer: buffer)
        }
        
        // Prepare and start the engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error.localizedDescription)")
        }
    }
    
    private func processBuffer(buffer: AVAudioPCMBuffer) {
        // If the sample rate already matches and it's mono, we can copy directly
        if buffer.format.sampleRate == targetSampleRate && buffer.format.channelCount == 1 {
            self.appendBufferData(buffer)
            return
        }
        guard let converter = self.converter else { return }
        let targetFormat = converter.outputFormat
        
        // Calculate the exact exact frame capacity needed to hold the converted buffer
        let capacity = AVAudioFrameCount(Double(buffer.frameCapacity) * (targetFormat.sampleRate / buffer.format.sampleRate))
        
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }
        
        var error: NSError? = nil
        var hasProvidedData = false
        
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if hasProvidedData {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedData = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        let status = converter.convert(to: targetBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error || error != nil {
            print("Error converting buffer: \(error?.localizedDescription ?? "Unknown error")")
            return
        }
        
        self.appendBufferData(targetBuffer)
    }
    
    private func appendBufferData(_ buffer: AVAudioPCMBuffer) {
        guard let floatChannelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channelData = UnsafeBufferPointer(start: floatChannelData[0], count: frameLength)
        
        // Append synchronously to avoid race conditions with stopRecording
        DispatchQueue.main.async {
            self.recordedData.append(contentsOf: Array(channelData))
        }
    }
    
    func stopRecording() -> [Float] {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        
        print("Stopped recording. Captured \(recordedData.count) frames at 16kHz.")
        return recordedData
    }
}

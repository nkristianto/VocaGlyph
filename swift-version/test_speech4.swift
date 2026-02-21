import Foundation
import AVFoundation
import Speech

@available(macOS 15.0, *)
func testSpeech() async {
    let authStatus = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
    print("Auth status: \(authStatus.rawValue)")
    
    let locale = Locale(identifier: "en-US")
    
    do {
        if #available(macOS 26.0, iOS 18.0, *) {
            let transcriberObj = SpeechTranscriber(locale: locale, preset: .transcription)
            let analyzerObj = SpeechAnalyzer(modules: [transcriberObj])
            print("Successfully instantiated")
        }
    } catch {
        print("Error instantiating: \(error)")
    }
}

if #available(macOS 15.0, *) {
    Task {
        await testSpeech()
        exit(0)
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))
}

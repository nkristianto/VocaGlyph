import Foundation
import Speech

if #available(macOS 15.0, *) {
    let t = type(of: SpeechTranscriber.Preset.self)
    print(t)
}

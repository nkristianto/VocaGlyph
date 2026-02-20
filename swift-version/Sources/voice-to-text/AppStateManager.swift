import Foundation
import Combine

enum AppState {
    case idle
    case recording
    case processing
}

protocol AppStateManagerDelegate: AnyObject {
    func appStateDidChange(newState: AppState)
}

class AppStateManager: ObservableObject {
    weak var delegate: AppStateManagerDelegate?
    
    @Published var currentState: AppState = .idle {
        didSet {
            delegate?.appStateDidChange(newState: currentState)
        }
    }
    
    func startRecording() {
        currentState = .recording
    }
    
    func stopRecording() {
        currentState = .processing
    }
    
    func setIdle() {
        currentState = .idle
    }
}

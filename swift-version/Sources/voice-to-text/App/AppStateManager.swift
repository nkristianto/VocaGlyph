import Foundation
import Combine

enum AppState {
    case idle
    case initializing
    case recording
    case processing
}

protocol AppStateManagerDelegate: AnyObject {
    func appStateDidChange(newState: AppState)
}

class AppStateManager: ObservableObject, @unchecked Sendable {
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
    
    func setInitializing() {
        currentState = .initializing
    }
}

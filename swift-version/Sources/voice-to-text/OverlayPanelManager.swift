import Cocoa
import SwiftUI

class OverlayPanelManager {
    static let shared = OverlayPanelManager()
    
    private var panel: NSPanel?
    
    func setupPanel(with stateManager: AppStateManager) {
        let overlayView = RecordingOverlayView(stateManager: stateManager)
        let hostingController = NSHostingController(rootView: overlayView)
        hostingController.view.backgroundFilters = [] // ensure view background is clear to allow panel transparency
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating // float above other windows
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] // show on all spaces
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentViewController = hostingController
        
        // Position at near-top center of main screen
        if let screen = NSScreen.main {
            let x = screen.frame.midX - 150
            let y = screen.frame.maxY - 120
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        self.panel = panel
    }
    
    func updateVisibility(for state: AppState) {
        guard let panel = panel else { return }
        
        if state == .idle {
            // Add a slight delay before closing to allow processing text to finish reading
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Ensure state is still idle before closing
                if let _ = panel.contentViewController?.view,
                   let hc = panel.contentViewController as? NSHostingController<RecordingOverlayView> {
                    if hc.rootView.stateManager.currentState == .idle {
                        panel.close()
                    }
                }
            }
        } else {
            // For .recording, .processing, and .initializing, show the panel
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
    }
}

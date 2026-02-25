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
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
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
        
        
        // We will position the panel dynamically in updateVisibility(for:)
        
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
                        panel.orderOut(nil)
                    }
                }
            }
        } else {
            // For .recording, .processing, and .initializing, show the panel
            if !panel.isVisible {
                // Determine the screen where the mouse currently is, or fallback to main
                let mouseLocation = NSEvent.mouseLocation
                let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
                
                if let screen = screen {
                    let width = panel.frame.width
                    let height = panel.frame.height
                    
                    // Use visibleFrame to account for the menu bar and notch.
                    // midX ensures it's perfectly centered horizontally.
                    let x = screen.visibleFrame.midX - (width / 2)
                    
                    // Place it 16 points below the menu bar (visibleFrame.maxY).
                    let y = screen.visibleFrame.maxY - height - 16
                    
                    panel.setFrameOrigin(NSPoint(x: x, y: y))
                }
                
                panel.orderFrontRegardless()
            }
        }
    }
}

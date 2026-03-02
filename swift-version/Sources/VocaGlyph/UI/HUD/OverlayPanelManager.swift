import Cocoa
import SwiftUI

class OverlayPanelManager: ObservableObject {
    static let shared = OverlayPanelManager()

    private var panel: NSPanel?

    /// The state the overlay UI should *display*.
    ///
    /// For non-idle transitions this updates immediately so the correct content
    /// (waveform, spinner, gear) is shown right away.
    ///
    /// For the `.idle` transition this is also updated immediately — but wrapped
    /// in `withAnimation` so SwiftUI plays the view's `.transition` (fade + scale).
    /// The NSPanel itself is kept open for an extra 0.25 s to let that animation
    /// complete before `orderOut` hides the window.
    ///
    /// This means the spinner disappears exactly when `setIdle()` fires (right
    /// after transcription finishes, right before the text is pasted), rather
    /// than lingering with an arbitrary fixed delay.
    @Published var displayState: AppState = .idle

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
            // Immediately animate displayState to .idle so the SwiftUI transition
            // (fade + scale defined on the view) plays right now — the spinner
            // disappears the instant transcription finishes, which is right before
            // the text is pasted into the focused app.
            withAnimation(.easeOut(duration: 0.2)) {
                displayState = .idle
            }
            // Keep the panel window open long enough for the transition to finish,
            // then close it.  0.25 s > the 0.2 s animation so the window never
            // disappears before the animation completes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak panel] in
                guard let self, let panel else { return }
                // Guard: only close if state is still idle to avoid closing a panel
                // that has already been re-shown for a new recording session.
                if let hc = panel.contentViewController as? NSHostingController<RecordingOverlayView>,
                   hc.rootView.stateManager.currentState == .idle {
                    panel.orderOut(nil)
                }
            }
        } else {
            // For .recording, .processing, and .initializing: show the correct
            // content immediately (no animation delay on appearance).
            displayState = state

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

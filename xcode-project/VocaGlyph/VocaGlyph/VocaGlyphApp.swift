import SwiftUI
import VocaGlyphLib

/// Xcode app entry point.
/// VocaGlyph is a pure AppKit/NSApplicationDelegate app (menu bar agent).
/// @NSApplicationDelegateAdaptor wires the existing AppDelegate into the SwiftUI
/// App lifecycle. AppDelegate source files are compiled directly in this target
/// (File → Add Files), not imported as a module, so no 'import VocaGlyph' needed.
@main
struct VocaGlyphApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // VocaGlyph has no main window — it's a menu bar agent.
        // Settings scene is required by App protocol but kept empty;
        // the real settings window is managed by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}

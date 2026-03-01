import SwiftUI

// MARK: - ShortcutRecorderButton

struct ShortcutRecorderButton: View {
    let displayLabel: String
    let onShortcutRecorded: (CGKeyCode, CGEventFlags) -> Void
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var localMonitor: Any?
    /// Tracks the peak modifier state seen during a recording session.
    /// Committed when the user starts releasing modifiers.
    @State private var peakFlags: CGEventFlags = []

    // Modifier-only key codes (not valid as a stand-alone primary key)
    private let invalidKeyCodes: Set<CGKeyCode> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Group {
                    if isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                            Text("Press keys…")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.red)
                        }
                    } else {
                        Text(displayLabel)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.navy)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isRecording ? Color.red.opacity(0.08) : Color.white)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.red.opacity(0.4) : Theme.textMuted.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.02), radius: 2, y: 1)
            .animation(.easeInOut(duration: 0.15), value: isRecording)

            // Reset button
            Button(action: {
                stopRecording()
                onReset()
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Reset to default (⌃ ⇧ C)")
        }
        .onDisappear { stopRecording() }
    }

    // MARK: - Recording State Machine

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    /// Extract the CGEventFlags from an NSEvent's modifierFlags.
    private func cgFlags(from nsFlags: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags = CGEventFlags()
        if nsFlags.contains(.control)  { flags.insert(.maskControl) }
        if nsFlags.contains(.option)   { flags.insert(.maskAlternate) }
        if nsFlags.contains(.shift)    { flags.insert(.maskShift) }
        if nsFlags.contains(.command)  { flags.insert(.maskCommand) }
        if nsFlags.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        return flags
    }

    private func startRecording() {
        isRecording = true
        peakFlags = []
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
            switch event.type {

            // ── Regular key + modifier combo ────────────────────────────────────
            case .keyDown:
                // Escape cancels without saving
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }

                let keyCode = CGKeyCode(event.keyCode)
                // Skip modifier-only key codes — wait for a regular key
                if invalidKeyCodes.contains(keyCode) { return nil }

                let flags = cgFlags(from: event.modifierFlags)

                // Require at least one modifier to avoid intercepting normal typing
                guard !flags.isEmpty else { return event }

                stopRecording()
                onShortcutRecorded(keyCode, flags)
                return nil // consume

            // ── Modifier-only combo ────────────────────────────────────────────
            case .flagsChanged:
                let flags = cgFlags(from: event.modifierFlags)

                let allTracked: [CGEventFlags] = [.maskAlphaShift, .maskControl, .maskAlternate, .maskShift, .maskCommand]
                let activeCount = allTracked.filter { flags.contains($0) }.count
                let peakCount  = allTracked.filter { peakFlags.contains($0) }.count

                if activeCount > peakCount {
                    // Modifiers still being added — update peak, don’t commit yet.
                    peakFlags = flags
                    return event
                } else if activeCount < peakCount, !peakFlags.isEmpty {
                    // A key was just released — commit whatever was held at peak.
                    let captured = peakFlags
                    stopRecording()
                    onShortcutRecorded(kModifierOnlyKeyCode, captured)
                    return nil // consume
                }
                // Active count unchanged (e.g. different modifier swapped) — ignore.
                return event

            default:
                break
            }

            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        peakFlags = []
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

import SwiftUI

// MARK: - ShortcutRecorderButton

struct ShortcutRecorderButton: View {
    let displayLabel: String
    let onShortcutRecorded: (CGKeyCode, CGEventFlags) -> Void
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var localMonitor: Any?

    // Modifier-only key codes (not valid as primary key)
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

    private func startRecording() {
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            // Escape cancels without saving
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let keyCode = CGKeyCode(event.keyCode)
            if invalidKeyCodes.contains(keyCode) { return nil }

            var flags = CGEventFlags()
            if event.modifierFlags.contains(.control)  { flags.insert(.maskControl) }
            if event.modifierFlags.contains(.option)   { flags.insert(.maskAlternate) }
            if event.modifierFlags.contains(.shift)    { flags.insert(.maskShift) }
            if event.modifierFlags.contains(.command)  { flags.insert(.maskCommand) }

            // Require at least one modifier to avoid intercepting normal typing
            guard !flags.isEmpty else { return event }

            stopRecording()
            onShortcutRecorded(keyCode, flags)
            return nil // consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

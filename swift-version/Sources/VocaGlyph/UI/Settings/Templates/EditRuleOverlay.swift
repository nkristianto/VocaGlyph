import SwiftUI

/// Floating overlay for editing an existing template rule.
struct EditRuleOverlay: View {
    @Binding var editingRuleText: String
    let onDismiss: () -> Void
    let onSave: (String) -> Void

    var isSaveDisabled: Bool {
        editingRuleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit Rule")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.navy)
                    Text("Describe one specific instruction for the AI.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $editingRuleText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.navy)
                .frame(minHeight: 80, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.textMuted.opacity(0.2), lineWidth: 1))

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.navy)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#F2EFE9"))
                    .clipShape(.rect(cornerRadius: 6))

                Button("Save") {
                    let trimmed = editingRuleText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onSave(trimmed) }
                    onDismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSaveDisabled ? Theme.accent.opacity(0.4) : Theme.accent)
                .clipShape(.rect(cornerRadius: 6))
                .disabled(isSaveDisabled)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 8)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

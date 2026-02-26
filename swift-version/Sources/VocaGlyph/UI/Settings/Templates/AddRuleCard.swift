import SwiftUI

/// "Add Rule" floating card inside TemplateEditorCard.
struct AddRuleCard: View {
    @Binding var ruleText: String
    let onDismiss: () -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add Rule")
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

            TextField("e.g. Remove filler words: um, uh, like", text: $ruleText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...5)
                .font(.system(size: 13))
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.textMuted.opacity(0.25), lineWidth: 1))
                .onSubmit {
                    if !ruleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onCommit()
                    }
                }

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

                Button("Add") { onCommit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ruleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Theme.accent.opacity(0.4) : Theme.accent)
                    .clipShape(.rect(cornerRadius: 6))
                    .disabled(ruleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 8)
    }
}

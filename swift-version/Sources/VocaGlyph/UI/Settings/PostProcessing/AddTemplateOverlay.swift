import SwiftUI

/// Floating "New Template" overlay card, extracted from PostProcessingSettingsView.
struct AddTemplateOverlay: View {
    @Binding var templateName: String
    let onDismiss: () -> Void
    let onCommit: () -> Void

    var body: some View {
        Color.black.opacity(0.25)
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture { onDismiss() }

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New Template")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.navy)
                    Text("Give your template a clear, descriptive name.")
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

            TextField("e.g. Customer Emails, Technical Docs…", text: $templateName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.textMuted.opacity(0.25), lineWidth: 1))
                .onSubmit {
                    if !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

                Button("Create") { onCommit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Theme.accent.opacity(0.4) : Theme.accent)
                    .clipShape(.rect(cornerRadius: 6))
                    .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 400)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 8)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

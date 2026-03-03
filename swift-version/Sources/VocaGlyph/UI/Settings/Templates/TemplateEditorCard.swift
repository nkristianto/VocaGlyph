import SwiftUI
import SwiftData

// MARK: - TemplateEditorCard

/// Floating card editor for a single template's name and free-text prompt.
/// Edits are kept in local draft state and only written to SwiftData when
/// the user taps "Save". This avoids unintentional auto-saves on every keystroke.
struct TemplateEditorCard: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var template: PostProcessingTemplate
    let onDismiss: () -> Void
    let onDeleteTemplate: () -> Void

    // Local draft state — written back to the model only on Save.
    @State private var draftName: String = ""
    @State private var draftPrompt: String = ""
    // Anchors for dirty-check — set once in onAppear.
    @State private var originalName: String = ""
    @State private var originalPrompt: String = ""

    private var isDirty: Bool {
        draftName != originalName || draftPrompt != originalPrompt
    }

    @State private var showResetConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false

    private var viewModel: TemplateEditorViewModel {
        TemplateEditorViewModel(modelContext: modelContext)
    }

    var isOverLength: Bool {
        draftPrompt.count > TemplatePromptRenderer.maxRecommendedPromptCharacters
    }

    var body: some View {
        ZStack {
            mainCard
            resetConfirmOverlay
            deleteConfirmOverlay
            discardConfirmOverlay
        }
        .animation(.easeInOut(duration: 0.15), value: showResetConfirm)
        .animation(.easeInOut(duration: 0.15), value: showDeleteConfirm)
        .animation(.easeInOut(duration: 0.15), value: showDiscardConfirm)
        .onAppear {
            draftName   = template.name
            draftPrompt = template.promptText
            originalName   = template.name
            originalPrompt = template.promptText
        }
    }

    // MARK: - Main Card

    @ViewBuilder
    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Template name", text: $draftName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.navy)
                        .textFieldStyle(.plain)
                    if template.isSystem {
                        Text("System template")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer()
                Button(action: handleDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(20)

            Divider().background(Theme.textMuted.opacity(0.15))

            promptEditor

            Divider().background(Theme.textMuted.opacity(0.15))

            footer
        }
        .frame(width: 480)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 8)
    }

    // MARK: - Prompt Editor

    @ViewBuilder
    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompt")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            TextEditor(text: $draftPrompt)
                .font(.system(size: 13))
                .foregroundStyle(Theme.navy)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(hex: "#F8F7F4"))
                .clipShape(.rect(cornerRadius: 8))
                .padding(.horizontal, 12)
                .frame(height: 200)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isOverLength {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text("Long prompts may reduce accuracy for local AI engines.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            HStack(spacing: 10) {
                // Reset / Delete (left side)
                if template.isSystem && !template.defaultPrompt.isEmpty {
                    Button("Reset to Default") {
                        withAnimation(.easeInOut(duration: 0.15)) { showResetConfirm = true }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.navy)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#F2EFE9"))
                    .clipShape(.rect(cornerRadius: 6))
                }

                if !template.isSystem {
                    Button("Delete Template") {
                        withAnimation(.easeInOut(duration: 0.15)) { showDeleteConfirm = true }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#EE6B6E"))
                    .clipShape(.rect(cornerRadius: 6))
                }

                Spacer()

                // Save (right side)
                Button("Save") {
                    commitSave()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isDirty ? Theme.accent : Theme.accent.opacity(0.4))
                .clipShape(.rect(cornerRadius: 6))
                .disabled(!isDirty)
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    private func commitSave() {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        template.name = trimmedName.isEmpty ? template.name : trimmedName
        template.promptText = draftPrompt
        template.updatedAt = Date()
        // Advance anchors so isDirty recomputes to false.
        originalName   = template.name
        originalPrompt = draftPrompt
        try? modelContext.save()
    }

    private func handleDismiss() {
        if isDirty {
            withAnimation(.easeInOut(duration: 0.15)) { showDiscardConfirm = true }
        } else {
            onDismiss()
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var resetConfirmOverlay: some View {
        if showResetConfirm {
            Color.black.opacity(0.10).ignoresSafeArea().transition(.opacity)
            CustomConfirmationDialog(
                title: "Reset to default prompt?",
                message: "Your custom changes will be lost. The original prompt will be restored.",
                confirmTitle: "Yes, reset it",
                cancelTitle: "Cancel",
                onConfirm: {
                    draftPrompt = template.defaultPrompt
                    draftName = template.name
                    // isDirty recomputes automatically from draft vs anchor comparison.
                    withAnimation(.easeInOut(duration: 0.15)) { showResetConfirm = false }
                },
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.15)) { showResetConfirm = false }
                }
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var deleteConfirmOverlay: some View {
        if showDeleteConfirm {
            Color.black.opacity(0.10).ignoresSafeArea().transition(.opacity)
            CustomConfirmationDialog(
                title: "Delete this template?",
                message: "This cannot be undone.",
                confirmTitle: "Yes, delete it",
                cancelTitle: "Cancel",
                onConfirm: {
                    showDeleteConfirm = false
                    onDeleteTemplate()
                    modelContext.delete(template)
                },
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.15)) { showDeleteConfirm = false }
                }
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var discardConfirmOverlay: some View {
        if showDiscardConfirm {
            Color.black.opacity(0.10).ignoresSafeArea().transition(.opacity)
            CustomConfirmationDialog(
                title: "Discard changes?",
                message: "You have unsaved changes. Close without saving?",
                confirmTitle: "Discard",
                cancelTitle: "Keep Editing",
                onConfirm: {
                    showDiscardConfirm = false
                    onDismiss()
                },
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.15)) { showDiscardConfirm = false }
                }
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }
}

import SwiftUI
import SwiftData

// MARK: - TemplateEditorCard

/// Floating card editor for a single template's name and ordered rules.
/// Styled to match the app's `CustomConfirmationDialog` popup pattern.
struct TemplateEditorCard: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var template: PostProcessingTemplate
    let onDismiss: () -> Void
    let onDeleteTemplate: () -> Void

    @State private var showAddRule = false
    @State private var newRuleText = ""
    @State private var showResetConfirm = false
    @State private var showDeleteConfirm = false
    @State private var editingRule: TemplateRule? = nil
    @State private var editingRuleText = ""

    private var viewModel: TemplateEditorViewModel {
        TemplateEditorViewModel(modelContext: modelContext)
    }

    var sortedRules: [TemplateRule] {
        template.rules.sorted { $0.order < $1.order }
    }

    var isOverLength: Bool {
        TemplatePromptRenderer.isOverRecommendedLength(template: template)
    }

    var body: some View {
        ZStack {
            mainCard
            addRuleOverlay
            resetConfirmOverlay
            deleteConfirmOverlay
            editRuleOverlay
        }
        .animation(.easeInOut(duration: 0.15), value: showAddRule)
        .animation(.easeInOut(duration: 0.15), value: showResetConfirm)
        .animation(.easeInOut(duration: 0.15), value: showDeleteConfirm)
        .animation(.easeInOut(duration: 0.15), value: editingRule == nil)
    }

    // MARK: - Main Card

    @ViewBuilder
    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Template name", text: $template.name)
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
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(20)

            Divider().background(Theme.textMuted.opacity(0.15))

            rulesList

            Divider().background(Theme.textMuted.opacity(0.15))

            footer
        }
        .frame(width: 480)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 8)
    }

    // MARK: - Rules List

    @ViewBuilder
    private var rulesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if template.rules.isEmpty {
                    HStack {
                        Spacer()
                        Text("No rules yet. Tap \"Add Rule\" below.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMuted)
                        Spacer()
                    }
                    .padding(20)
                } else {
                    ForEach(sortedRules) { rule in
                        ruleRow(rule)
                        if rule.id != sortedRules.last?.id {
                            Divider()
                                .background(Theme.textMuted.opacity(0.1))
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .frame(height: 200)
    }

    @ViewBuilder
    private func ruleRow(_ rule: TemplateRule) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { rule.isEnabled = $0; template.updatedAt = Date() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            Text(rule.instruction)
                .font(.system(size: 13))
                .foregroundStyle(rule.isEnabled ? Theme.navy : Theme.textMuted)
                .strikethrough(!rule.isEnabled, color: Theme.textMuted.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            Button {
                editingRuleText = rule.instruction
                withAnimation(.easeInOut(duration: 0.15)) { editingRule = rule }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Edit rule")

            Button {
                template.rules.removeAll { $0.id == rule.id }
                modelContext.delete(rule)
                viewModel.reorderRules(in: template)
                template.updatedAt = Date()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#EE6B6E"))
            }
            .buttonStyle(.plain)
            .help("Delete rule")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                    Text("Too many rules may reduce accuracy for local AI engines.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            HStack(spacing: 10) {
                Button {
                    newRuleText = ""
                    withAnimation(.easeInOut(duration: 0.15)) { showAddRule = true }
                } label: {
                    Label("Add Rule", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                if template.isSystem && !template.defaultRules.isEmpty {
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
            }
        }
        .padding(16)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var addRuleOverlay: some View {
        if showAddRule {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { showAddRule = false }
                }
            AddRuleCard(
                ruleText: $newRuleText,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.15)) { showAddRule = false }
                },
                onCommit: {
                    viewModel.commitAddRule(to: template, text: newRuleText)
                    newRuleText = ""
                    withAnimation(.easeInOut(duration: 0.15)) { showAddRule = false }
                }
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var resetConfirmOverlay: some View {
        if showResetConfirm {
            Color.black.opacity(0.10).ignoresSafeArea().transition(.opacity)
            CustomConfirmationDialog(
                title: "Reset to default rules?",
                message: "Your custom changes will be lost. The original rules will be restored.",
                confirmTitle: "Yes, reset it",
                cancelTitle: "Cancel",
                onConfirm: {
                    viewModel.resetToDefaults(template: template)
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
    private var editRuleOverlay: some View {
        if let rule = editingRule {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { editingRule = nil }
                }
            EditRuleOverlay(
                editingRuleText: $editingRuleText,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.15)) { editingRule = nil }
                },
                onSave: { trimmed in
                    rule.instruction = trimmed
                    template.updatedAt = Date()
                }
            )
        }
    }
}

import SwiftUI

/// Coordinator view for the Writing Assistant settings tab.
/// Owns the new-template overlay and template editor overlay state.
/// Sections appear in order: AI Refinement → Basic Cleanup → Word Replacements.
struct TextProcessingSettingsView: View {
    @ObservedObject var whisper: WhisperService
    @ObservedObject var stateManager: AppStateManager
    @ObservedObject var viewModel: SettingsViewModel

    @AppStorage("enablePostProcessing") private var enablePostProcessing: Bool = false

    @Environment(\.modelContext) private var modelContext

    @State private var editingTemplate: PostProcessingTemplate? = nil
    @State private var showAddTemplate = false
    @State private var newTemplateName = ""

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Sticky Header — no experimental badge on title (AC #6)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Writing Assistant")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.navy)
                    Text("AI refinement, cleanup rules, and word corrections for your dictations")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.8))

                Divider().background(Theme.textMuted.opacity(0.1))

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // 1. AI Refinement (experimental badge on section header, not page title)
                        TemplateAwareAISection(
                            stateManager: stateManager,
                            viewModel: viewModel,
                            onEditTemplate: { template in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    editingTemplate = template
                                }
                            },
                            onAddTemplate: {
                                newTemplateName = ""
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showAddTemplate = true
                                }
                            }
                        )

                        // 2. Basic Cleanup
                        BasicCleanupSection()

                        // 3. Word Replacements
                        WordReplacementSection()
                    }
                    .padding(40)
                    .padding(.bottom, 20)
                }
            }

            // Template editor overlay
            if let template = editingTemplate {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editingTemplate = nil }
                    }

                TemplateEditorCard(
                    template: template,
                    onDismiss: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editingTemplate = nil }
                    },
                    onDeleteTemplate: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editingTemplate = nil }
                    }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // New template overlay
            if showAddTemplate {
                AddTemplateOverlay(
                    templateName: $newTemplateName,
                    onDismiss: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showAddTemplate = false }
                    },
                    onCommit: { commitNewTemplate() }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: editingTemplate == nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAddTemplate)
    }

    // MARK: - Actions

    @MainActor
    private func commitNewTemplate() {
        let name = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = PostProcessingTemplate(name: name.isEmpty ? "Untitled" : name, isSystem: false)
        modelContext.insert(t)
        UserDefaults.standard.set(t.id.uuidString, forKey: TemplateSeederService.activeTemplateKey)
        showAddTemplate = false
        newTemplateName = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editingTemplate = t }
    }
}

// MARK: - TemplateAwareAISection
// Wraps AIPostProcessingSection and wires the template section callbacks
// so we avoid passing closures through multiple layers of sub-views.

private struct TemplateAwareAISection: View {
    @ObservedObject var stateManager: AppStateManager
    @ObservedObject var viewModel: SettingsViewModel
    let onEditTemplate: (PostProcessingTemplate) -> Void
    let onAddTemplate: () -> Void

    @AppStorage("enablePostProcessing") private var enablePostProcessing: Bool = false
    @AppStorage("selectedTaskModel") private var selectedTaskModel: String = "apple-native"
    @AppStorage("selectedCloudProvider") private var selectedCloudProvider: String = "gemini"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header: "AI Refinement" with inline experimental badge (AC #6)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label {
                    Text("AI Refinement")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.navy)
                } icon: {
                    Image(systemName: "wand.and.stars").foregroundStyle(Theme.navy)
                }
                // Text("experimental")
                //     .font(.system(size: 10, weight: .medium))
                //     .foregroundStyle(Color.orange.opacity(0.9))
            }

            VStack(spacing: 0) {
                enableToggleRow

                if enablePostProcessing {
                    Divider().background(Theme.textMuted.opacity(0.1))
                    modelPickerRow
                    appleIntelligenceCheck
                    localLLMSubSection
                    cloudAPISubSection
                    Divider().background(Theme.textMuted.opacity(0.1))
                    TemplateListSection(onEdit: onEditTemplate, onAddTemplate: onAddTemplate)
                }
            }
            .background(Color.white)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.textMuted.opacity(0.2), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var enableToggleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Automated Text Refinement")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.navy)
                Text("Use an AI engine to fix grammar and rephrase text before pasting")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { enablePostProcessing },
                set: { newValue in
                    enablePostProcessing = newValue
                    stateManager.onPostProcessingToggled(isEnabled: newValue)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(16)
    }

    @ViewBuilder
    private var modelPickerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Processing Model")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.navy)
                Text("Select the AI to refine your text")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Menu {
                Button("Apple Intelligence") {
                    Logger.shared.debug("Settings: Changed AI Processing Model to 'apple-native'")
                    selectedTaskModel = "apple-native"
                    stateManager.switchPostProcessingEngine()
                }
                Button("Cloud API (Gemini/Anthropic)") {
                    Logger.shared.debug("Settings: Changed AI Processing Model to 'cloud-api'")
                    selectedTaskModel = "cloud-api"
                    stateManager.switchPostProcessingEngine()
                }
                Button("Local AI (Qwen)") {
                    Logger.shared.debug("Settings: Changed AI Processing Model to 'local-llm'")
                    selectedTaskModel = "local-llm"
                    stateManager.switchPostProcessingEngine()
                }
            } label: {
                HStack {
                    let display = selectedTaskModel == "apple-native" ? "Apple Intelligence"
                        : selectedTaskModel == "cloud-api" ? "Cloud API (Gemini/Anthropic)"
                        : selectedTaskModel == "local-llm" ? "Local AI (Qwen)"
                        : selectedTaskModel
                    Text(display).font(.system(size: 13)).foregroundStyle(Theme.navy)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 160)
        }
        .padding(16)
    }

    @ViewBuilder
    private var appleIntelligenceCheck: some View {
        if selectedTaskModel == "apple-native" {
            AppleIntelligenceStatusBadge()
        }
    }

    @ViewBuilder
    private var localLLMSubSection: some View {
        if selectedTaskModel == "local-llm" {
            Divider().background(Theme.textMuted.opacity(0.1))
            LocalLLMSection(stateManager: stateManager)
            Divider().background(Theme.textMuted.opacity(0.1))
            LLMParametersSection()
        }
    }

    @ViewBuilder
    private var cloudAPISubSection: some View {
        if selectedTaskModel == "cloud-api" {
            Divider().background(Theme.textMuted.opacity(0.1))
            cloudProviderPicker
            Divider().background(Theme.textMuted.opacity(0.1))
            ErrorDisplaySection(errorMessage: viewModel.errorMessage)
            ExternalApiCredentialsSection(viewModel: viewModel, selectedCloudProvider: selectedCloudProvider)
            Divider().background(Theme.textMuted.opacity(0.1))
            LLMParametersSection()
        }
    }

    @ViewBuilder
    private var cloudProviderPicker: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud Provider")
                    .fontWeight(.semibold).foregroundStyle(Theme.navy)
                Text("Select the external AI service to use")
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Menu {
                Button("Google Gemini") {
                    Logger.shared.debug("Settings: Changed Cloud Provider to 'gemini'")
                    selectedCloudProvider = "gemini"
                    stateManager.switchPostProcessingEngine()
                }
                Button("Anthropic Claude") {
                    Logger.shared.debug("Settings: Changed Cloud Provider to 'anthropic'")
                    selectedCloudProvider = "anthropic"
                    stateManager.switchPostProcessingEngine()
                }
            } label: {
                HStack {
                    Text(selectedCloudProvider == "anthropic" ? "Anthropic Claude" : "Google Gemini")
                        .font(.system(size: 13)).foregroundStyle(Theme.navy)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 160)
        }
        .padding(16)
    }
}

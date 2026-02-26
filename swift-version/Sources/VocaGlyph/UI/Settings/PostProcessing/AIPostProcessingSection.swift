import SwiftUI

/// AI Post-Processing section: main toggle, model selection, and conditional sub-sections.
struct AIPostProcessingSection: View {
    @ObservedObject var stateManager: AppStateManager
    @ObservedObject var viewModel: SettingsViewModel

    @AppStorage("enablePostProcessing") private var enablePostProcessing: Bool = false
    @AppStorage("selectedTaskModel") private var selectedTaskModel: String = "apple-native"
    @AppStorage("selectedCloudProvider") private var selectedCloudProvider: String = "gemini"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("AI Post-Processing")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            } icon: {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Theme.navy)
            }

            VStack(spacing: 0) {
                // Enable Post-Processing Toggle
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

                if enablePostProcessing {
                    Divider().background(Theme.textMuted.opacity(0.1))
                    modelPickerRow
                    appleIntelligenceCheck
                    localLLMSubSection
                    cloudAPISubSection
                    Divider().background(Theme.textMuted.opacity(0.1))
                    TemplateListSection(
                        onEdit: { _ in },   // parent PostProcessingSettingsView handles this
                        onAddTemplate: {}    // parent handles this
                    )
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

    // MARK: - Model Picker

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
                    Text(display)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.navy)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 160)
        }
        .padding(16)
    }

    // MARK: - Conditional sub-sections

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
            LLMParametersSection()
        }
    }

    @ViewBuilder
    private var cloudProviderPicker: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud Provider")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.navy)
                Text("Select the external AI service to use")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
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
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.navy)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 160)
        }
        .padding(16)
    }
}

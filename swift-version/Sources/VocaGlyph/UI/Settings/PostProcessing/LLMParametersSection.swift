import SwiftUI

/// Collapsible Advanced Settings section: Temperature, Top-P, and Repetition Penalty sliders.
struct LLMParametersSection: View {
    @AppStorage(LLMInferenceConfiguration.temperatureKey) private var llmTemperature: Double = 0.0
    @AppStorage(LLMInferenceConfiguration.topPKey) private var llmTopP: Double = 1.0
    @AppStorage(LLMInferenceConfiguration.repetitionPenaltyKey) private var llmRepetitionPenalty: Double = 1.0
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Disclosure toggle row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                    Text("Advanced Settings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.navy)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(Theme.textMuted.opacity(0.1))

                VStack(alignment: .leading, spacing: 12) {
                    // Reset button row
                    HStack {
                        Text("Fine-tune how the model generates its output")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                        Spacer()
                        Button("Reset") {
                            llmTemperature = 0.0
                            llmTopP = 1.0
                            llmRepetitionPenalty = 1.0
                            Logger.shared.info("Settings: LLM parameters reset to defaults")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.background)
                        .clipShape(.rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.textMuted.opacity(0.2), lineWidth: 1))
                    }

                    temperatureSlider
                    Divider().background(Theme.textMuted.opacity(0.08))
                    topPSlider
                    Divider().background(Theme.textMuted.opacity(0.08))
                    repetitionPenaltySlider
                }
                .padding(16)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Sliders

    @ViewBuilder
    private var temperatureSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Temperature")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.navy)
                Spacer()
                Text(String(format: "%.2f", llmTemperature))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, alignment: .trailing)
            }
            Slider(value: $llmTemperature, in: 0.0...1.0, step: 0.05).tint(Theme.accent)
            HStack(spacing: 4) {
                Image(systemName: "thermometer.low").font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                Text("Controls randomness. Lower = more precise, stays faithful to your words. Higher = more creative, may paraphrase.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
        }
    }

    @ViewBuilder
    private var topPSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Focus (Top-P)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.navy)
                Spacer()
                Text(String(format: "%.2f", llmTopP))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, alignment: .trailing)
            }
            Slider(value: $llmTopP, in: 0.5...1.0, step: 0.05).tint(Theme.accent)
            HStack(spacing: 4) {
                Image(systemName: "scope").font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                Text("Nucleus sampling. Filters out low-probability word choices. Lower = more focused, higher = more flexible.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
        }
    }

    @ViewBuilder
    private var repetitionPenaltySlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Repetition Penalty")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.navy)
                Spacer()
                Text(String(format: "%.2f", llmRepetitionPenalty))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, alignment: .trailing)
            }
            Slider(value: $llmRepetitionPenalty, in: 1.0...1.3, step: 0.05).tint(Theme.accent)
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                Text("Penalises repeated words to avoid loops. 1.0 = off. Values above 1.1 may slightly affect quality.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

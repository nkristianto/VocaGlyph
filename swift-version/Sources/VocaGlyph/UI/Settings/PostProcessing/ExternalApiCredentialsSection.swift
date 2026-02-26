import SwiftUI

/// External API Credentials section — Gemini and Anthropic keychain fields.
struct ExternalApiCredentialsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    let selectedCloudProvider: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("External API Credentials")
                .fontWeight(.semibold)
                .foregroundStyle(Theme.navy)
            Text("Securely save your keys in macOS Keychain. They are never stored in plaintext.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)

            if selectedCloudProvider == "anthropic" {
                anthropicKeyField
            }

            if selectedCloudProvider == "gemini" {
                geminiKeyField
            }
        }
        .padding(16)
        .background(Color.white)
    }

    // MARK: - Anthropic Key

    @ViewBuilder
    private var anthropicKeyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Anthropic API Key")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.navy)

            HStack(spacing: 8) {
                SecureField(viewModel.isAnthropicKeySaved ? "sk-ant-... (Saved in Keychain)" : "sk-ant-...", text: $viewModel.anthropicApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))

                pasteButton { viewModel.anthropicApiKey = $0 }

                if viewModel.isAnthropicKeySaved {
                    Button(action: { Task { @MainActor in await viewModel.deleteAnthropicKey() } }) {
                        Text("Delete").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .help("Key is securely stored in Keychain")
                } else {
                    Button(action: { Task { @MainActor in await viewModel.saveAnthropicKey() } }) {
                        Text("Save Securely").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.anthropicApiKey.isEmpty)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Gemini Key

    @ViewBuilder
    private var geminiKeyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Gemini API Key")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.navy)

            HStack(spacing: 8) {
                SecureField(viewModel.isGeminiKeySaved ? "AIzaSy... (Saved in Keychain)" : "AIzaSy...", text: $viewModel.geminiApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))

                pasteButton { viewModel.geminiApiKey = $0 }

                if viewModel.isGeminiKeySaved {
                    Button(action: { Task { @MainActor in await viewModel.deleteGeminiKey() } }) {
                        Text("Delete").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .help("Key is securely stored in Keychain")
                } else {
                    Button(action: { Task { @MainActor in await viewModel.saveGeminiKey() } }) {
                        Text("Save Securely").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.geminiApiKey.isEmpty)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func pasteButton(onPaste: @escaping (String) -> Void) -> some View {
        Button(action: {
            if let str = NSPasteboard.general.string(forType: .string) {
                onPaste(str)
            }
        }) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .help("Paste from clipboard")
    }
}

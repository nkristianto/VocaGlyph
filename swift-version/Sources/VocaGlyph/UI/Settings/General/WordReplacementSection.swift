import SwiftUI
import SwiftData

// MARK: - WordReplacementSection

struct WordReplacementSection: View {

    @Query(sort: \WordReplacement.createdAt, order: .forward)
    private var replacements: [WordReplacement]

    @Environment(\.modelContext) private var modelContext

    // Add form state
    @State private var isAddingNew = false
    @State private var newWord = ""
    @State private var newReplacement = ""

    // Edit form state
    @State private var editingItem: WordReplacement? = nil
    @State private var editWord = ""
    @State private var editReplacement = ""

    @State private var viewModel: WordReplacementViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Header ────────────────────────────────────────────────────────
            Label {
                Text("Word Replacements")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            } icon: {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(Theme.navy)
            }

            // ── Card Body ─────────────────────────────────────────────────────
            VStack(spacing: 0) {
                if replacements.isEmpty && !isAddingNew {
                    Text("No replacements yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else {
                    ForEach(replacements) { item in
                        if item != replacements.first {
                            Divider().background(Theme.textMuted.opacity(0.1))
                        }
                        if editingItem?.id == item.id {
                            editForm(for: item)
                        } else {
                            replacementRow(for: item)
                        }
                    }

                    if isAddingNew {
                        if !replacements.isEmpty {
                            Divider().background(Theme.textMuted.opacity(0.1))
                        }
                        addForm
                    }
                }

                // ── Add Button ─────────────────────────────────────────────────
                if !isAddingNew && editingItem == nil {
                    Divider().background(Theme.textMuted.opacity(0.1))
                    Button {
                        isAddingNew = true
                    } label: {
                        Label("Add Replacement", systemImage: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.white)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.textMuted.opacity(0.2), lineWidth: 1)
            )
        }
        .onAppear {
            if viewModel == nil {
                viewModel = WordReplacementViewModel(modelContext: modelContext)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func replacementRow(for item: WordReplacement) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.word)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.navy)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                    Text(item.replacement)
                        .foregroundStyle(Theme.navy)
                }
                .font(.system(size: 13))
            }

            Spacer()

            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { item.isEnabled },
                set: { _ in vm.toggleEnabled(item) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            // Edit button
            // .borderless fixes SwiftUI gesture-absorption bug in rows that contain Toggle
            Button {
                editWord = item.word
                editReplacement = item.replacement
                editingItem = item
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.borderless)

            // Delete button
            Button {
                vm.deleteReplacement(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
    }

    // MARK: - Edit Form

    @ViewBuilder
    private func editForm(for item: WordReplacement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                    TextField("e.g. gonna", text: $editWord)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.textMuted.opacity(0.3), lineWidth: 1))
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Replacement")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                    TextField("e.g. going to", text: $editReplacement)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.textMuted.opacity(0.3), lineWidth: 1))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    editingItem = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMuted)

                Button("Save") {
                    vm.updateReplacement(item, word: editWord, replacement: editReplacement)
                    editingItem = nil
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 13, weight: .medium))
                .disabled(editWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          editReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(Theme.background.opacity(0.5))
    }

    // MARK: - Add Form

    @ViewBuilder
    private var addForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                    TextField("e.g. gonna", text: $newWord)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.textMuted.opacity(0.3), lineWidth: 1))
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Replacement")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                    TextField("e.g. going to", text: $newReplacement)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.textMuted.opacity(0.3), lineWidth: 1))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    resetAddForm()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMuted)

                Button("Add") {
                    vm.addReplacement(word: newWord, replacement: newReplacement)
                    resetAddForm()
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 13, weight: .medium))
                .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          newReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var vm: WordReplacementViewModel {
        if let viewModel { return viewModel }
        return WordReplacementViewModel(modelContext: modelContext)
    }

    private func resetAddForm() {
        newWord = ""
        newReplacement = ""
        isAddingNew = false
    }
}

import SwiftUI
import SwiftData

// MARK: - WordReplacementViewModel

/// ViewModel encapsulating all `ModelContext`-mutating operations for `WordReplacementSection`.
/// By injecting `ModelContext` this class can be unit-tested with an in-memory container.
///
/// Each mutating method calls `modelContext.save()` after the change so that
/// the `@Query` in `WordReplacementSection` sees the update immediately without
/// requiring a navigation round-trip.
@MainActor
final class WordReplacementViewModel {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Add Replacement

    /// Inserts a new `WordReplacement` record into the context.
    /// Does nothing if either `word` or `replacement` is empty after trimming.
    func addReplacement(word: String, replacement: String) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty, !trimmedReplacement.isEmpty else { return }
        let item = WordReplacement(word: trimmedWord, replacement: trimmedReplacement)
        modelContext.insert(item)
        try? modelContext.save()
    }

    // MARK: - Update Replacement

    /// Updates the word and replacement text on an existing pair.
    /// Does nothing if either field is empty after trimming.
    func updateReplacement(_ item: WordReplacement, word: String, replacement: String) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty, !trimmedReplacement.isEmpty else { return }
        item.word = trimmedWord
        item.replacement = trimmedReplacement
        try? modelContext.save()
    }

    // MARK: - Delete Replacement

    /// Permanently removes a `WordReplacement` record from the context.
    func deleteReplacement(_ item: WordReplacement) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    // MARK: - Toggle Enabled

    /// Flips the `isEnabled` flag on the given replacement pair.
    func toggleEnabled(_ item: WordReplacement) {
        item.isEnabled.toggle()
        try? modelContext.save()
    }
}

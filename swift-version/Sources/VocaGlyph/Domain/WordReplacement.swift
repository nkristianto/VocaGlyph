import Foundation
import SwiftData

// MARK: - WordReplacement

/// A single word/phrase replacement pair stored in SwiftData.
///
/// When `isEnabled` is `true`, the applicator will substitute every
/// case-insensitive whole-word occurrence of `word` with `replacement`
/// in the transcription pipeline (Stage 1.7).
@Model
public final class WordReplacement {

    // MARK: - Stored Properties

    @Attribute(.unique) public var id: UUID
    public var word: String
    public var replacement: String
    public var isEnabled: Bool
    public var createdAt: Date

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        word: String,
        replacement: String,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.word = word
        self.replacement = replacement
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

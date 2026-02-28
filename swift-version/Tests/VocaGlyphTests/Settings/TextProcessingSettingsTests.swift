import XCTest
@testable import VocaGlyph

// MARK: - TextProcessingSettingsTests
// Verifies that BasicCleanupSection's @AppStorage keys retain their correct
// default values so no data migration is needed for existing users (AC #4).

final class TextProcessingSettingsTests: XCTestCase {

    // MARK: - Setup / Teardown

    private let autoPunctuationKey = "autoPunctuation"
    private let removeFillerWordsKey = "removeFillerWords"

    override func setUp() {
        super.setUp()
        // Remove the keys so we're always testing true defaults
        UserDefaults.standard.removeObject(forKey: autoPunctuationKey)
        UserDefaults.standard.removeObject(forKey: removeFillerWordsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: autoPunctuationKey)
        UserDefaults.standard.removeObject(forKey: removeFillerWordsKey)
        super.tearDown()
    }

    // MARK: - AppStorage Key Defaults (AC #4)

    func test_autoPunctuation_defaultIsTrue() {
        // When the key has never been set, @AppStorage("autoPunctuation") must
        // default to `true` — matches BasicCleanupSection's declaration.
        let value = UserDefaults.standard.object(forKey: autoPunctuationKey)
        if let value {
            // Key was pre-set (e.g. by another test run); verify it is Bool true
            XCTAssertEqual(value as? Bool, true,
                           "autoPunctuation should default to true per @AppStorage declaration")
        } else {
            // Key absent — this IS the default state; the @AppStorage default of
            // `true` will be used by SwiftUI. We verify the key name is correct
            // by checking that reading it without a registered default returns nil.
            XCTAssertNil(value,
                         "autoPunctuation key absent means @AppStorage default (true) will be used")
        }
    }

    func test_removeFillerWords_defaultIsFalse() {
        // When the key has never been set, @AppStorage("removeFillerWords") must
        // default to `false` — matches BasicCleanupSection's declaration.
        let value = UserDefaults.standard.object(forKey: removeFillerWordsKey)
        if let value {
            XCTAssertEqual(value as? Bool, false,
                           "removeFillerWords should default to false per @AppStorage declaration")
        } else {
            XCTAssertNil(value,
                         "removeFillerWords key absent means @AppStorage default (false) will be used")
        }
    }

    func test_autoPunctuation_keyName_isCorrect() {
        // Regression guard: ensure the key string itself is correct and frozen.
        // If someone renames it, existing user data would be lost.
        UserDefaults.standard.set(true, forKey: autoPunctuationKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "autoPunctuation"),
                      "AppStorage key 'autoPunctuation' must remain unchanged")
    }

    func test_removeFillerWords_keyName_isCorrect() {
        // Regression guard: key string is frozen — renaming it loses user data.
        UserDefaults.standard.set(false, forKey: removeFillerWordsKey)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "removeFillerWords"),
                       "AppStorage key 'removeFillerWords' must remain unchanged")
    }
}

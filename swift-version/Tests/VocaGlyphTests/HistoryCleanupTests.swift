import XCTest
import SwiftData
@testable import voice_to_text

@MainActor
final class HistoryCleanupTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var appDelegate: AppDelegate!
    
    override func setUpWithError() throws {
        let schema = Schema([TranscriptionItem.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        context = container.mainContext
        
        appDelegate = AppDelegate()
        appDelegate.sharedModelContainer = container
        appDelegate.output = OutputService() // Initialize to prevent crash
    }
    
    override func tearDownWithError() throws {
        container = nil
        context = nil
        appDelegate = nil
    }
    
    func testCleanupRemovesItemsOlderThan30Days() throws {
        let now = Date()
        let calendar = Calendar.current
        
        // Item precisely 31 days old (should be purged)
        let thirtyOneDaysAgo = calendar.date(byAdding: .day, value: -31, to: now)!
        let oldItem = TranscriptionItem(id: UUID(), text: "Old dictation", timestamp: thirtyOneDaysAgo)
        context.insert(oldItem)
        
        // Item 10 days old (should be kept)
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        let mediumItem = TranscriptionItem(id: UUID(), text: "Medium dictation", timestamp: tenDaysAgo)
        context.insert(mediumItem)
        
        // Item from exactly right now (should be kept)
        let recentItem = TranscriptionItem(id: UUID(), text: "Recent dictation", timestamp: now)
        context.insert(recentItem)
        
        try context.save()
        
        // Verify we start with 3 items
        let initialItems = try context.fetch(FetchDescriptor<TranscriptionItem>())
        XCTAssertEqual(initialItems.count, 3)
        
        // Trigger a fake transcription to run the cleanup logic inside it
        appDelegate.appStateManagerDidTranscribe(text: "New dictation")
        
        // Wait for the async Task { @MainActor } inside appStateManagerDidTranscribe to finish
        let expectation = XCTestExpectation(description: "Wait for background SwiftData cleanup task to complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Fetch remaining items
        let postCleanupItems = try context.fetch(FetchDescriptor<TranscriptionItem>())
        
        // We expect: Medium, Recent, and the newly added "New dictation" (Total 3)
        // The old item should be removed
        XCTAssertEqual(postCleanupItems.count, 3)
        
        // Ensure old item is dead
        XCTAssertFalse(postCleanupItems.contains(where: { $0.id == oldItem.id }), "Old item was not deleted.")
        
        // Ensure medium item is kept
        XCTAssertTrue(postCleanupItems.contains(where: { $0.id == mediumItem.id }), "Medium item was incorrectly deleted.")
        
        // Ensure recent item is kept
        XCTAssertTrue(postCleanupItems.contains(where: { $0.id == recentItem.id }), "Recent item was incorrectly deleted.")
    }
}

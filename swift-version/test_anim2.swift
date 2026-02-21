import AppKit

@available(macOS 14.0, *)
func testAnim(item: NSStatusItem) {
    let btn = item.button
    btn?.imageView?.removeAllSymbolEffects()
    btn?.addSymbolEffect(.pulse) // Also see if addSymbolEffect exists directly on NSButton?
}

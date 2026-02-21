import AppKit

@available(macOS 14.0, *)
func testAnim(button: NSButton) {
    button.imageView?.removeAllSymbolEffects()
    if #available(macOS 15.0, *) {
        button.imageView?.addSymbolEffect(.rotate, options: .repeating)
    } else {
        button.imageView?.addSymbolEffect(.pulse, options: .repeating)
    }
}

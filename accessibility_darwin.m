#import "accessibility_darwin.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

char *get_active_context_text(int max_chars) {
  @autoreleasepool {
    // Check if we have Accessibility permissions silently.
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt : @(NO)};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
      return NULL;
    }

    AXUIElementRef systemWideElement = AXUIElementCreateSystemWide();
    if (!systemWideElement)
      return NULL;

    AXUIElementRef focusedApp = NULL;
    AXError err = AXUIElementCopyAttributeValue(systemWideElement,
                                                kAXFocusedApplicationAttribute,
                                                (CFTypeRef *)&focusedApp);
    if (err != kAXErrorSuccess || !focusedApp) {
      CFRelease(systemWideElement);
      return NULL;
    }

    AXUIElementRef focusedUIElement = NULL;
    err =
        AXUIElementCopyAttributeValue(focusedApp, kAXFocusedUIElementAttribute,
                                      (CFTypeRef *)&focusedUIElement);
    CFRelease(focusedApp);
    CFRelease(systemWideElement);

    if (err != kAXErrorSuccess || !focusedUIElement) {
      return NULL;
    }

    // Try getting the selected text range to find the cursor position
    CFTypeRef selectedRangeValue = NULL;
    err = AXUIElementCopyAttributeValue(
        focusedUIElement, kAXSelectedTextRangeAttribute, &selectedRangeValue);

    int cursor_position = 0;
    if (err == kAXErrorSuccess && selectedRangeValue) {
      CFRange range;
      if (AXValueGetValue((AXValueRef)selectedRangeValue, kAXValueCFRangeType,
                          &range)) {
        cursor_position = (int)range.location;
      }
      CFRelease(selectedRangeValue);
    }

    // Get the full text content of the focused element
    CFTypeRef textValue = NULL;
    err = AXUIElementCopyAttributeValue(focusedUIElement, kAXValueAttribute,
                                        &textValue);
    CFRelease(focusedUIElement);

    if (err != kAXErrorSuccess || !textValue) {
      return NULL;
    }

    NSString *fullText = (__bridge NSString *)textValue;
    if (!fullText || [fullText length] == 0) {
      CFRelease(textValue);
      return NULL;
    }

    // We only want the text *before* the cursor to provide leading context
    if (cursor_position <= 0) {
      CFRelease(textValue);
      return NULL;
    }

    if (cursor_position > [fullText length]) {
      cursor_position = (int)[fullText length];
    }

    int start_idx = cursor_position - max_chars;
    if (start_idx < 0)
      start_idx = 0;

    NSRange contextRange = NSMakeRange(start_idx, cursor_position - start_idx);
    NSString *contextText = [fullText substringWithRange:contextRange];

    const char *utf8Str = [contextText UTF8String];
    char *result = NULL;
    if (utf8Str) {
      result = strdup(utf8Str);
    }

    CFRelease(textValue);
    return result;
  }
}

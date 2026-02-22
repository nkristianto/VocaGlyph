#import "keystroke_darwin.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

bool post_keystrokes(const char *text) {
  if (!text || strlen(text) == 0) {
    return false;
  }

  @autoreleasepool {
    NSString *nsText = [NSString stringWithUTF8String:text];
    if (!nsText)
      return false;

    NSUInteger len = [nsText length];
    unichar *buffer = malloc(len * sizeof(unichar));
    [nsText getCharacters:buffer range:NSMakeRange(0, len)];

    // We use kCGSessionEventTap to post events.
    CGEventSourceRef source =
        CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!source) {
      free(buffer);
      return false;
    }

    // Post each character as a generic keydown/keyup event with unicode payload
    for (NSUInteger i = 0; i < len; i++) {
      UniChar c = buffer[i];

      // 0 is virtual keycode for 'A' but the system uses the unicode string
      // when provided
      CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 0, true);
      CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 0, false);

      CGEventKeyboardSetUnicodeString(keyDown, 1, &c);
      CGEventKeyboardSetUnicodeString(keyUp, 1, &c);

      CGEventPost(kCGHIDEventTap, keyDown);
      CGEventPost(kCGHIDEventTap, keyUp);

      CFRelease(keyDown);
      CFRelease(keyUp);
    }

    CFRelease(source);
    free(buffer);
    return true;
  }
}

bool is_accessibility_trusted(bool prompt) {
  NSDictionary *options =
      @{(__bridge id)kAXTrustedCheckOptionPrompt : @(prompt)};
  return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

#ifndef keystroke_darwin_h
#define keystroke_darwin_h

#include <stdbool.h>
#include <stdint.h>

// Post string as keystrokes. Returns true on success, false on failure to
// create events.
bool post_keystrokes(const char *text);

// Check if the application is a trusted accessibility client. If prompt is
// true, it prompts the user.
bool is_accessibility_trusted(bool prompt);

#endif /* keystroke_darwin_h */

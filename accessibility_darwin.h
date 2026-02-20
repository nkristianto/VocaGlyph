#ifndef accessibility_darwin_h
#define accessibility_darwin_h

#include <stdbool.h>

// Gets the text before the cursor in the currently focused application field.
// Returns a dynamically allocated string containing up to max_chars characters.
// Returns NULL if it fails or if accessibility permissions are denied.
// The caller is responsible for freeing the returned string using free().
char *get_active_context_text(int max_chars);

#endif /* accessibility_darwin_h */

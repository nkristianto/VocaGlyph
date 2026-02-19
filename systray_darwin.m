// systray_darwin.m — Objective-C NSStatusItem implementation for voice-to-text.
// This file is compiled once by CGo via the standard Go build system.
// Placing ObjC class definitions here (not in a CGo preamble) avoids
// the duplicate-symbol linker error that occurs when CGo compiles
// preamble code into multiple translation units.

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

// Callbacks exported from Go via //export.
extern void goToggleWindowCallback(void);
extern void goQuitCallback(void);

// _SysTrayTarget handles menu item actions.
// We intentionally do NOT touch AppDelegate to avoid conflicts with Wails.
@interface _SysTrayTarget : NSObject
- (void)handleShowHide:(id)sender;
- (void)handleQuit:(id)sender;
@end

@implementation _SysTrayTarget
- (void)handleShowHide:(id)sender {
  goToggleWindowCallback();
}
- (void)handleQuit:(id)sender {
  goQuitCallback();
}
@end

static NSStatusItem *_statusItem = nil;
static _SysTrayTarget *_sysTrayTarget = nil;

static void initSysTrayOnMain(NSData *imgData) {
  if (_statusItem != nil)
    return;

  _statusItem = [[NSStatusBar systemStatusBar]
      statusItemWithLength:NSVariableStatusItemLength];
  [_statusItem retain];

  // Icon
  NSImage *img = [[NSImage alloc] initWithData:imgData];
  [img setTemplate:YES];
  [img setSize:NSMakeSize(18, 18)];
  [[_statusItem button] setImage:img];
  [[_statusItem button] setToolTip:@"voice-to-text"];
  [img release];

  // Target for menu item actions
  _sysTrayTarget = [[_SysTrayTarget alloc] init];

  // Build a drop-down NSMenu (shown on left-click via setMenu:)
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"voice-to-text"];

  NSMenuItem *showItem =
      [[NSMenuItem alloc] initWithTitle:@"Show / Hide"
                                 action:@selector(handleShowHide:)
                          keyEquivalent:@""];
  [showItem setTarget:_sysTrayTarget];
  [menu addItem:showItem];
  [showItem release];

  [menu addItem:[NSMenuItem separatorItem]];

  NSMenuItem *quitItem =
      [[NSMenuItem alloc] initWithTitle:@"Quit voice-to-text"
                                 action:@selector(handleQuit:)
                          keyEquivalent:@"q"];
  [quitItem setTarget:_sysTrayTarget];
  [menu addItem:quitItem];
  [quitItem release];

  [_statusItem setMenu:menu];
  [menu release];
}

void dispatchSysTray(const unsigned char *pngData, int pngLen) {
  NSData *copy = [NSData dataWithBytes:pngData length:(NSUInteger)pngLen];
  dispatch_async(dispatch_get_main_queue(), ^{
    initSysTrayOnMain(copy);
  });
}

void dispatchHideFromDock(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSApplication sharedApplication]
        setActivationPolicy:NSApplicationActivationPolicyAccessory];
  });
}

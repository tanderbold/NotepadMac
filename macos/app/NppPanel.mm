#import "NppPanel.h"

@interface NppPanel ()
@property (nonatomic) BOOL hasBeenPlaced;
@end

@implementation NppPanel

/// Escape reaches here through the responder chain when nothing else claims it.
- (void)cancelOperation:(id)sender {
    [self orderOut:sender];
}

/// Puts the panel somewhere sensible the first time it is shown.
///
/// A window made with a content rectangle at the origin sits in the bottom left
/// corner of the screen, which is where every one of these panels was appearing.
/// Where the user last put it is better than the middle, so that is tried first.
- (void)placeIfNeeded {
    if (self.hasBeenPlaced) return;
    self.hasBeenPlaced = YES;

    NSString *name = self.title.length
        ? [@"NppPanel." stringByAppendingString:self.title] : nil;
    if (name && [self setFrameAutosaveName:name] && [self setFrameUsingName:name]) return;
    [self center];
}

- (void)makeKeyAndOrderFront:(id)sender {
    [self placeIfNeeded];
    [super makeKeyAndOrderFront:sender];
}

- (void)orderFront:(id)sender {
    [self placeIfNeeded];
    [super orderFront:sender];
}

- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWindow {
    if (place != NSWindowOut) [self placeIfNeeded];
    [super orderWindow:place relativeTo:otherWindow];
}

@end

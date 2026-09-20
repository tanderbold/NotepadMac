// Builds macos/resources/AppIcon.icns: the Windows application icon (the
// 256-pixel image of PowerEditor/src/icons/npp.ico) on a macOS icon tile,
// with a ⌘ badge in the corner that says which Notepad++ this is.
//   clang -fobjc-arc -framework Cocoa macos/make_icon.m -o /tmp/make_icon && /tmp/make_icon <repo root>
#import <Cocoa/Cocoa.h>

static NSBitmapImageRep *Canvas(int px) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:px pixelsHigh:px bitsPerSample:8
                                              samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                               colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
}

static NSBitmapImageRep *Render(NSImage *art, int px) {
    NSBitmapImageRep *rep = Canvas(px);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationHigh;
    CGFloat s = px / 1024.0;
    NSAffineTransform *scale = [NSAffineTransform transform];
    [scale scaleBy:s];
    [scale concat];

    // The tile: Apple's grid puts an 824-point rounded square in a 1024 canvas.
    NSRect tile = NSMakeRect(100, 100, 824, 824);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:tile xRadius:186 yRadius:186];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.30];
    shadow.shadowOffset = NSMakeSize(0, -12);
    shadow.shadowBlurRadius = 28;
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [[NSColor whiteColor] setFill];
    [shape fill];
    [NSGraphicsContext restoreGraphicsState];
    [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:1.0 alpha:1]
                                   endingColor:[NSColor colorWithRed:0.86 green:0.90 blue:0.86 alpha:1]] drawInBezierPath:shape angle:-90];
    [[NSColor colorWithWhite:0 alpha:0.10] setStroke];
    shape.lineWidth = 2;
    [shape stroke];

    // The Windows icon, whole, inside the tile.
    [NSGraphicsContext saveGraphicsState];
    [shape addClip];
    [art drawInRect:NSMakeRect(172, 182, 680, 680) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    // The badge: ⌘, the key no other system has.
    NSRect badge = NSMakeRect(610, 96, 330, 330);
    NSBezierPath *disc = [NSBezierPath bezierPathWithOvalInRect:badge];
    NSShadow *lift = [[NSShadow alloc] init];
    lift.shadowColor = [NSColor colorWithWhite:0 alpha:0.35];
    lift.shadowOffset = NSMakeSize(0, -6);
    lift.shadowBlurRadius = 16;
    [NSGraphicsContext saveGraphicsState];
    [lift set];
    [[NSColor whiteColor] setFill];
    [disc fill];
    [NSGraphicsContext restoreGraphicsState];
    NSBezierPath *inner = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(badge, 14, 14)];
    [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithRed:0.30 green:0.33 blue:0.38 alpha:1]
                                   endingColor:[NSColor colorWithRed:0.11 green:0.12 blue:0.15 alpha:1]] drawInBezierPath:inner angle:-90];
    NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:210 weight:NSFontWeightSemibold],
                            NSForegroundColorAttributeName: [NSColor whiteColor]};
    NSString *glyph = @"⌘";
    NSSize size = [glyph sizeWithAttributes:attrs];
    [glyph drawAtPoint:NSMakePoint(NSMidX(badge) - size.width / 2, NSMidY(badge) - size.height / 2 + 4) withAttributes:attrs];

    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *root = argc > 1 ? @(argv[1]) : @".";
        NSString *ico = [root stringByAppendingPathComponent:@"PowerEditor/src/icons/npp.ico"];
        NSImage *all = [[NSImage alloc] initWithContentsOfFile:ico];
        // The biggest image in the .ico is the one to draw from.
        NSImageRep *best = nil;
        for (NSImageRep *r in all.representations) if (!best || r.pixelsWide > best.pixelsWide) best = r;
        if (!best) { fprintf(stderr, "cannot read %s\n", ico.UTF8String); return 1; }
        NSImage *art = [[NSImage alloc] initWithSize:NSMakeSize(best.pixelsWide, best.pixelsHigh)];
        [art addRepresentation:best];

        NSString *set = [NSTemporaryDirectory() stringByAppendingPathComponent:@"NotepadMac.iconset"];
        [[NSFileManager defaultManager] removeItemAtPath:set error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:set withIntermediateDirectories:YES attributes:nil error:NULL];
        for (NSArray *e in @[@[@16, @"16x16"], @[@32, @"16x16@2x"], @[@32, @"32x32"], @[@64, @"32x32@2x"], @[@128, @"128x128"],
                             @[@256, @"128x128@2x"], @[@256, @"256x256"], @[@512, @"256x256@2x"], @[@512, @"512x512"], @[@1024, @"512x512@2x"]]) {
            NSData *png = [Render(art, [e[0] intValue]) representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [png writeToFile:[set stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%@.png", e[1]]] atomically:YES];
        }
        NSString *out = [root stringByAppendingPathComponent:@"macos/resources/AppIcon.icns"];
        NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/iconutil" arguments:@[@"-c", @"icns", set, @"-o", out]];
        [task waitUntilExit];
        printf("%s (from %ldx%ld)\n", out.UTF8String, (long)best.pixelsWide, (long)best.pixelsHigh);
        return task.terminationStatus;
    }
}

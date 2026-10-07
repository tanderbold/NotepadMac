// Builds macos/resources/AppIcon.icns and docs/icon.png (512 px) from the icon's artwork,
// macos/resources/icon-source.png: a rounded square on a dark ground. NotepadMac's own picture -
// nothing of Notepad++'s (no chameleon, no wordmark): NotepadMac is a port of Notepad++, not Notepad++.
//   clang -fobjc-arc -framework Cocoa macos/make_icon.m -o /tmp/make_icon && /tmp/make_icon <repo root> [<folder for the PNGs>]
// The square is found in the picture and set on Apple's grid (an 824-point body in a 1024 canvas,
// 185-point corners, a soft shadow); at 64 pixels and below the head alone is drawn, which still
// reads at the Finder's list sizes where the whole figure does not.
#import <Cocoa/Cocoa.h>

/// The picture's square: how far the pixels lighter than the ground reach along the lines through
/// its middle, in the bitmap's top-left coordinates turned to the image's bottom-left ones.
static NSRect SquareOf(NSBitmapImageRep *src) {
    NSInteger W = src.pixelsWide, H = src.pixelsHigh;
    NSInteger x0 = W, x1 = 0, y0 = H, y1 = 0;
    for (NSInteger x = 0; x < W; ++x) {
        NSUInteger p[4]; [src getPixel:p atX:x y:H / 2];
        if (p[0] + p[1] + p[2] > 3 * 48) { x0 = MIN(x0, x); x1 = MAX(x1, x); }
    }
    for (NSInteger y = 0; y < H; ++y) {
        NSUInteger p[4]; [src getPixel:p atX:W / 2 y:y];
        if (p[0] + p[1] + p[2] > 3 * 48) { y0 = MIN(y0, y); y1 = MAX(y1, y); }
    }
    return NSMakeRect(x0, H - 1 - y1, x1 - x0 + 1, y1 - y0 + 1);
}

static NSData *Render(NSImage *art, NSRect square, NSInteger s) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:s pixelsHigh:s bitsPerSample:8
                                                                samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                 colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    ctx.imageInterpolation = NSImageInterpolationHigh;
    NSGraphicsContext.currentContext = ctx;
    CGFloat k = s / 1024.0;
    NSRect body = NSMakeRect(100 * k, 100 * k, 824 * k, 824 * k);
    NSBezierPath *round = [NSBezierPath bezierPathWithRoundedRect:body xRadius:185 * k yRadius:185 * k];
    // A shadow's offset and blur are in pixels whatever the transform: scaled here.
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.3];
    shadow.shadowOffset = NSMakeSize(0, -10 * k);
    shadow.shadowBlurRadius = 18 * k;
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [[NSColor blackColor] setFill];
    [round fill];
    [NSGraphicsContext restoreGraphicsState];
    [round addClip];
    NSRect from = square;
    if (s <= 64) {
        CGFloat side = square.size.width * 0.56;
        from = NSMakeRect(NSMidX(square) - side / 2 - square.size.width * 0.01,
                          NSMaxY(square) - side - square.size.height * 0.07, side, side);
    }
    [art drawInRect:body fromRect:from operation:NSCompositingOperationCopy fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *root = argc > 1 ? @(argv[1]) : @".";
        NSString *source = [root stringByAppendingPathComponent:@"macos/resources/icon-source.png"];
        NSBitmapImageRep *src = (NSBitmapImageRep *)[NSBitmapImageRep imageRepWithContentsOfFile:source];
        if (![src isKindOfClass:[NSBitmapImageRep class]]) { fprintf(stderr, "cannot read %s\n", source.UTF8String); return 1; }
        NSRect square = SquareOf(src);
        NSImage *art = [[NSImage alloc] initWithSize:NSMakeSize(src.pixelsWide, src.pixelsHigh)];
        [art addRepresentation:src];

        NSString *set = argc > 2 ? [@(argv[2]) stringByAppendingPathComponent:@"NotepadMac.iconset"]
                                 : [NSTemporaryDirectory() stringByAppendingPathComponent:@"NotepadMac.iconset"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:set error:NULL];
        [fm createDirectoryAtPath:set withIntermediateDirectories:YES attributes:nil error:NULL];
        NSMutableDictionary<NSNumber *, NSData *> *pngs = [NSMutableDictionary dictionary];
        for (NSNumber *n in @[@16, @32, @64, @128, @256, @512, @1024]) pngs[n] = Render(art, square, n.integerValue);
        for (NSNumber *n in @[@16, @32, @128, @256, @512]) {
            [pngs[n] writeToFile:[set stringByAppendingFormat:@"/icon_%@x%@.png", n, n] atomically:YES];
            [pngs[@(n.integerValue * 2)] writeToFile:[set stringByAppendingFormat:@"/icon_%@x%@@2x.png", n, n] atomically:YES];
        }
        // The web site's icon is the 512-pixel image.
        [pngs[@512] writeToFile:[root stringByAppendingPathComponent:@"docs/icon.png"] atomically:YES];
        NSString *out = [root stringByAppendingPathComponent:@"macos/resources/AppIcon.icns"];
        NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/iconutil" arguments:@[@"-c", @"icns", set, @"-o", out]];
        [task waitUntilExit];
        printf("%s, %s (square %.0f,%.0f %.0fx%.0f of the picture)\n", out.UTF8String, set.UTF8String,
               square.origin.x, square.origin.y, square.size.width, square.size.height);
        return task.terminationStatus;
    }
}

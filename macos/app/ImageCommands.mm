// OCR by Vision, QR both ways by Vision and Core Image - the system engines,
// no bundled models. Everything works on the clipboard or the selection and
// puts its answer at the caret with one undo step, like the MIME conversions.
#import "ImageCommands.h"
#import "MimeCommands.h"
#import "ScintillaView.h"
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

@implementation EditorController (ImageCommands)

+ (NSImage *)clipboardImage {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSArray *read = [pb readObjectsForClasses:@[[NSImage class]] options:nil];
    if ([read.firstObject isKindOfClass:[NSImage class]]) return read.firstObject;
    // A file copied in Finder arrives as its URL, not its pixels.
    NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                               options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in urls) {
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
        if (image) return image;
    }
    return nil;
}

+ (NSString *)textRecognizedInCGImage:(CGImageRef)cg {
    if (!cg) return nil;
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    if (@available(macOS 13.0, *)) request.automaticallyDetectsLanguage = YES;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    if (![handler performRequests:@[request] error:NULL]) return nil;

    // Vision's boxes have their origin at the bottom left; reading order is
    // top to bottom, then left to right.
    NSArray<VNRecognizedTextObservation *> *found =
        [request.results sortedArrayUsingComparator:^NSComparisonResult(VNRecognizedTextObservation *a,
                                                                        VNRecognizedTextObservation *b) {
            if (fabs(a.boundingBox.origin.y - b.boundingBox.origin.y) > 0.01)
                return a.boundingBox.origin.y > b.boundingBox.origin.y ? NSOrderedAscending : NSOrderedDescending;
            return a.boundingBox.origin.x < b.boundingBox.origin.x ? NSOrderedAscending : NSOrderedDescending;
        }];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (VNRecognizedTextObservation *observation in found) {
        NSString *best = [observation topCandidates:1].firstObject.string;
        if (best.length) [lines addObject:best];
    }
    return lines.count ? [lines componentsJoinedByString:@"\n"] : nil;
}

+ (NSString *)textRecognizedInImage:(NSImage *)image {
    return [self textRecognizedInCGImage:[image CGImageForProposedRect:NULL context:nil hints:nil]];
}

+ (NSString *)textRecognizedInFileAt:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    if ([path.pathExtension caseInsensitiveCompare:@"pdf"] == NSOrderedSame) {
        CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)url);
        if (!pdf) return nil;
        NSMutableArray<NSString *> *pages = [NSMutableArray array];
        size_t pageCount = CGPDFDocumentGetNumberOfPages(pdf);
        for (size_t number = 1; number <= pageCount; ++number) {
            CGPDFPageRef page = CGPDFDocumentGetPage(pdf, number);
            if (!page) continue;
            // Drawn large enough to read: the recognizer wants print-like
            // resolution, ~2200 pixels along the long side.
            CGRect box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
            CGFloat scale = 2200 / MAX(box.size.width, box.size.height);
            size_t w = (size_t)(box.size.width * scale), hgt = (size_t)(box.size.height * scale);
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(NULL, w, hgt, 8, 0, space,
                                                     kCGImageAlphaPremultipliedFirst);
            CGColorSpaceRelease(space);
            if (!ctx) continue;
            CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
            CGContextFillRect(ctx, CGRectMake(0, 0, w, hgt));
            CGContextScaleCTM(ctx, scale, scale);
            CGContextTranslateCTM(ctx, -box.origin.x, -box.origin.y);
            CGContextDrawPDFPage(ctx, page);
            CGImageRef cg = CGBitmapContextCreateImage(ctx);
            CGContextRelease(ctx);
            NSString *text = [self textRecognizedInCGImage:cg];
            CGImageRelease(cg);
            if (text.length) [pages addObject:text];
        }
        CGPDFDocumentRelease(pdf);
        return pages.count ? [pages componentsJoinedByString:@"\n\n"] : nil;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    return image ? [self textRecognizedInImage:image] : nil;
}

/// Core Image on the processor: the default context wants a GPU, which a
/// headless runner (and so CI) does not have.
static CIContext *SoftwareCIContext(void) {
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @YES}];
    });
    return context;
}

+ (NSImage *)qrImageFromText:(NSString *)text side:(CGFloat)side {
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:[text dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *raw = filter.outputImage;
    if (!raw) return nil;   // the text does not fit the format
    CGFloat scale = MAX(1, floor(side / raw.extent.size.width));
    CIImage *scaled = [raw imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CGImageRef cg = [SoftwareCIContext() createCGImage:scaled fromRect:scaled.extent];
    if (!cg) return nil;
    NSImage *image = [[NSImage alloc] initWithCGImage:cg size:scaled.extent.size];
    CGImageRelease(cg);
    return image;
}

+ (NSString *)textFromQRCodesInImage:(NSImage *)image {
    CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cg) return nil;
    VNDetectBarcodesRequest *request = [[VNDetectBarcodesRequest alloc] init];
    request.symbologies = @[VNBarcodeSymbologyQR];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    if (![handler performRequests:@[request] error:NULL]) return nil;
    NSArray<VNBarcodeObservation *> *found =
        [request.results sortedArrayUsingComparator:^NSComparisonResult(VNBarcodeObservation *a,
                                                                        VNBarcodeObservation *b) {
            return a.boundingBox.origin.y > b.boundingBox.origin.y ? NSOrderedAscending : NSOrderedDescending;
        }];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (VNBarcodeObservation *observation in found) {
        if (observation.payloadStringValue.length) [texts addObject:observation.payloadStringValue];
    }
    if (!texts.count) {
        // Vision leans on hardware a runner may not have; the Core Image
        // detector reads the same codes on the processor.
        CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                                  context:SoftwareCIContext()
                                                  options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
        NSArray<CIFeature *> *features =
            [detector featuresInImage:[CIImage imageWithCGImage:cg]];
        for (CIQRCodeFeature *feature in features) {
            if ([feature isKindOfClass:[CIQRCodeFeature class]] && feature.messageString.length)
                [texts addObject:feature.messageString];
        }
    }
    return texts.count ? [texts componentsJoinedByString:@"\n"] : nil;
}

- (BOOL)pasteImageAsText {
    NSImage *image = [EditorController clipboardImage];
    if (!image) return NO;
    NSString *text = [EditorController textRecognizedInImage:image];
    if (!text.length) return NO;
    [self.sci message:SCI_BEGINUNDOACTION];
    [self.sci setStringProperty:SCI_REPLACESEL parameter:0 value:text];
    [self.sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
    return YES;
}

- (BOOL)insertTextFromClipboardQR {
    NSImage *image = [EditorController clipboardImage];
    if (!image) return NO;
    NSString *text = [EditorController textFromQRCodesInImage:image];
    if (!text.length) return NO;
    [self.sci message:SCI_BEGINUNDOACTION];
    [self.sci setStringProperty:SCI_REPLACESEL parameter:0 value:text];
    [self.sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
    return YES;
}

@end

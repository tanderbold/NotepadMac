// The Markdown preview: cmark renders the document (CMARK_OPT_UNSAFE keeps
// the raw HTML Markdown is allowed to carry, and what the table pre-pass
// makes), a WKWebView shows it with JavaScript off, and the panel re-renders,
// debounced, whenever the editor's chrome says something changed - which
// typing does. Relative image paths resolve against the document's folder,
// which the page is loaded under as npp-preview://file/<folder>/ and whose
// files a scheme handler of the panel's own serves: WebKit gives a page
// loaded from a string no read access to file: URLs, so a file: base left
// the images out (and, in a sandboxed WebContent process, the page blank).
// Nothing is fetched from the network (a remote image would tell its server
// the file was opened, and from where) and the preview never navigates away
// from the document: a link clicked opens in the browser, as MarkdownViewer++
// sends every navigation to the default browser (webBrowserPreview_Navigating).
#import "MarkdownPanel.h"
#import "EditorController.h"
#import "DockingManager.h"
#import "PluginHost.h"
#import "ScintillaView.h"
#import <WebKit/WebKit.h>
#import "cmark.h"

static NSString *const kPreviewScheme = @"npp-preview";

/// npp-preview://file/<absolute path>: the file at that path, read here and handed to WebKit
/// (images, a stylesheet beside the document). Only files are served, never a listing, and
/// with no JavaScript in the page there is nothing that could read one and send it on.
@interface NppPreviewFiles : NSObject <WKURLSchemeHandler>
@end

@implementation NppPreviewFiles
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    NSURL *url = task.request.URL;
    NSString *path = url.path.stringByStandardizingPath;
    BOOL isDirectory = YES;
    NSData *data = nil;
    if ([url.host isEqualToString:@"file"] && path.isAbsolutePath &&
        [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory)
        data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data) {
        [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil]];
        return;
    }
    // What a Markdown page refers to; WebKit sniffs an image whose type it is not told.
    NSDictionary<NSString *, NSString *> *types = @{
        @"png": @"image/png", @"jpg": @"image/jpeg", @"jpeg": @"image/jpeg", @"gif": @"image/gif", @"webp": @"image/webp",
        @"svg": @"image/svg+xml", @"bmp": @"image/bmp", @"ico": @"image/x-icon", @"tif": @"image/tiff", @"tiff": @"image/tiff",
        @"heic": @"image/heic", @"css": @"text/css", @"woff": @"font/woff", @"woff2": @"font/woff2", @"ttf": @"font/ttf",
        @"otf": @"font/otf", @"mp4": @"video/mp4", @"mov": @"video/quicktime", @"mp3": @"audio/mpeg", @"wav": @"audio/wav"};
    NSString *type = types[path.pathExtension.lowercaseString] ?: @"application/octet-stream";
    [task didReceiveResponse:[[NSURLResponse alloc] initWithURL:url MIMEType:type expectedContentLength:(NSInteger)data.length textEncodingName:nil]];
    [task didReceiveData:data];
    [task didFinish];
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {}
@end

@interface MarkdownPanel () <WKNavigationDelegate>
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic) WKWebView *webView;
@property (nonatomic, copy) NSString *lastHTML;
@property (nonatomic, nullable) NSURL *baseURL;     // what the page was loaded under
@property (nonatomic) NSUInteger loadsPending;     // loadHTMLString calls not yet let through
@end

@implementation MarkdownPanel

+ (NSString *)renderInline:(NSString *)text {
    // A table cell keeps its inline Markdown: rendered on its own, then the
    // enclosing <p> that cmark wraps a lone line in is taken off.
    const char *utf8 = text.UTF8String ?: "";
    char *html = cmark_markdown_to_html(utf8, strlen(utf8), CMARK_OPT_UNSAFE);
    NSString *piece = [[NSString stringWithUTF8String:html] ?: @""
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    free(html);
    if ([piece hasPrefix:@"<p>"] && [piece hasSuffix:@"</p>"])
        piece = [piece substringWithRange:NSMakeRange(3, piece.length - 7)];
    return piece;
}

/// Splits a table row on unescaped pipes; \| stays a literal | in the cell.
+ (NSArray<NSString *> *)tableCellsOf:(NSString *)row {
    NSString *line = [row stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([line hasPrefix:@"|"]) line = [line substringFromIndex:1];
    if ([line hasSuffix:@"|"] && ![line hasSuffix:@"\\|"])
        line = [line substringToIndex:line.length - 1];
    NSMutableArray *cells = [NSMutableArray array];
    NSMutableString *cell = [NSMutableString string];
    for (NSUInteger i = 0; i < line.length; ++i) {
        unichar c = [line characterAtIndex:i];
        if (c == '\\' && i + 1 < line.length && [line characterAtIndex:i + 1] == '|') {
            [cell appendString:@"|"]; ++i;
        } else if (c == '|') {
            [cells addObject:[cell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
            [cell setString:@""];
        } else {
            [cell appendFormat:@"%C", c];
        }
    }
    [cells addObject:[cell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    return cells;
}

/// The delimiter row's cells, as alignments; nil when the row is not one.
+ (NSArray<NSString *> *)tableAlignmentsOf:(NSString *)row {
    NSArray<NSString *> *cells = [self tableCellsOf:row];
    if (![row containsString:@"-"]) return nil;
    NSMutableArray *aligns = [NSMutableArray array];
    for (NSString *cell in cells) {
        if (![cell length]) return nil;
        BOOL left = [cell hasPrefix:@":"], right = [cell hasSuffix:@":"];
        NSString *dashes = [cell stringByTrimmingCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@": "]];
        if (!dashes.length) return nil;
        for (NSUInteger i = 0; i < dashes.length; ++i)
            if ([dashes characterAtIndex:i] != '-') return nil;
        [aligns addObject:left && right ? @"center" : right ? @"right" : left ? @"left" : @""];
    }
    return aligns;
}

+ (NSString *)tablesToHTML:(NSString *)markdown {
    NSArray<NSString *> *lines = [markdown componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSUInteger i = 0;
    BOOL inFence = NO;
    while (i < lines.count) {
        NSString *line = lines[i];
        NSString *bare = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([bare hasPrefix:@"```"] || [bare hasPrefix:@"~~~"]) inFence = !inFence;
        // A table starts at a | line whose next line is the :---|---: rule.
        NSArray *aligns = nil;
        if (!inFence && [bare containsString:@"|"] && i + 1 < lines.count &&
            [lines[i + 1] containsString:@"|"]) {
            aligns = [self tableAlignmentsOf:lines[i + 1]];
        }
        if (!aligns) { [out addObject:line]; ++i; continue; }

        NSArray<NSString *> *headers = [self tableCellsOf:line];
        NSMutableString *table = [NSMutableString stringWithString:@"<table>\n<thead>\n<tr>"];
        NSString *(^align)(NSUInteger) = ^NSString *(NSUInteger column) {
            NSString *a = column < [aligns count] ? aligns[column] : @"";
            return a.length ? [NSString stringWithFormat:@" style=\"text-align:%@\"", a] : @"";
        };
        for (NSUInteger c = 0; c < headers.count; ++c)
            [table appendFormat:@"<th%@>%@</th>", align(c), [self renderInline:headers[c]]];
        [table appendString:@"</tr>\n</thead>\n<tbody>\n"];
        i += 2;
        while (i < lines.count) {
            NSString *rowLine = [lines[i] stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceCharacterSet]];
            if (![rowLine containsString:@"|"] || !rowLine.length) break;
            [table appendString:@"<tr>"];
            NSArray<NSString *> *cells = [self tableCellsOf:rowLine];
            // GFM: short rows pad out, long rows are cut to the header's width.
            for (NSUInteger c = 0; c < headers.count; ++c)
                [table appendFormat:@"<td%@>%@</td>", align(c),
                 c < cells.count ? [self renderInline:cells[c]] : @""];
            [table appendString:@"</tr>\n"];
            ++i;
        }
        [table appendString:@"</tbody>\n</table>"];
        [out addObject:table];
    }
    return [out componentsJoinedByString:@"\n"];
}

+ (NSString *)htmlFromMarkdown:(NSString *)markdown {
    NSString *withTables = [self tablesToHTML:markdown ?: @""];
    const char *utf8 = withTables.UTF8String ?: "";
    char *html = cmark_markdown_to_html(utf8, strlen(utf8), CMARK_OPT_UNSAFE);
    NSString *body = [NSString stringWithUTF8String:html] ?: @"";
    free(html);
    return body;
}

- (instancetype)initWithEditor:(EditorController *)editor {
    if ((self = [super init])) {
        _editor = editor;
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        // The preview shows; it must not run. Markdown's raw HTML stays inert.
        config.defaultWebpagePreferences.allowsContentJavaScript = NO;
        [config setURLSchemeHandler:[[NppPreviewFiles alloc] init] forURLScheme:kPreviewScheme];
        _webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 500) configuration:config];
        _webView.navigationDelegate = self;
        _openLink = ^(NSURL *url) { [[NSWorkspace sharedWorkspace] openURL:url]; };
        [[NppDockingManager shared] registerPanel:@"markdownPreview" title:@"Markdown Preview"
                                             view:_webView defaultPlace:NppDockRight];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentChanged:)
                                                     name:NppEditorDocumentsDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (BOOL)visible { return [[NppDockingManager shared] isPanelVisible:@"markdownPreview"]; }

- (void)toggle {
    if (self.visible) { [[NppDockingManager shared] hidePanel:@"markdownPreview"]; return; }
    [[NppDockingManager shared] showPanel:@"markdownPreview"];
    [self refresh];
}

- (void)documentChanged:(NSNotification *)note {
    if (!self.visible) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refresh) object:nil];
    [self performSelector:@selector(refresh) withObject:nil afterDelay:0.3];
}

- (void)refresh {
    NSString *markdown = [self.editor.sci string] ?: @"";
    NSString *body = [MarkdownPanel htmlFromMarkdown:markdown];
    NSString *page = [NSString stringWithFormat:
        @"<!doctype html><html><head><meta charset=\"utf-8\">\n"
        // Before anything of the document's: a policy a later <meta> cannot loosen. Local files
        // (the document's own images) load; nothing from the network does.
        @"<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src npp-preview: data:; "
        @"style-src 'unsafe-inline' npp-preview:; font-src npp-preview: data:; media-src npp-preview: data:\">\n"
        @"<meta http-equiv=\"x-dns-prefetch-control\" content=\"off\">\n"
        @"<style>\n"
        @"body { font: 14px -apple-system, sans-serif; margin: 12px 16px; color: CanvasText; background: Canvas; color-scheme: light dark; }\n"
        @"pre, code { font-family: ui-monospace, Menlo, monospace; font-size: 12px; }\n"
        @"pre { background: color-mix(in srgb, CanvasText 8%%, Canvas); padding: 8px 10px; border-radius: 6px; overflow-x: auto; }\n"
        @"code { background: color-mix(in srgb, CanvasText 8%%, Canvas); padding: 1px 4px; border-radius: 4px; }\n"
        @"pre code { background: none; padding: 0; }\n"
        @"blockquote { border-left: 3px solid color-mix(in srgb, CanvasText 25%%, Canvas); margin-left: 0; padding-left: 12px; opacity: .85; }\n"
        @"table { border-collapse: collapse; } th, td { border: 1px solid color-mix(in srgb, CanvasText 25%%, Canvas); padding: 4px 8px; }\n"
        @"img { max-width: 100%%; }\n"
        @"a { color: LinkText; }\n"
        @"</style></head><body>%@</body></html>", body];
    self.lastHTML = page;
    NSString *folder = self.editor.currentDocument.path.stringByDeletingLastPathComponent;
    NSURL *base = nil;
    if (folder.length) {
        NSURLComponents *parts = [[NSURLComponents alloc] init];
        parts.scheme = kPreviewScheme;
        parts.host = @"file";
        parts.path = [folder hasSuffix:@"/"] ? folder : [folder stringByAppendingString:@"/"];
        base = parts.URL;
    }
    self.baseURL = base;
    self.loadsPending++;
    [self.webView loadHTMLString:page baseURL:base];
}

static NSString *WithoutFragment(NSURL *url) {
    NSString *text = url.absoluteString ?: @"";
    NSRange hash = [text rangeOfString:@"#"];
    return hash.location == NSNotFound ? text : [text substringToIndex:hash.location];
}

/// The page given to loadHTMLString goes in; a jump to an anchor of it too. Anything else - a
/// link, a <meta http-equiv=refresh>, a form, a frame - would put another page in the preview's
/// place: it is stopped, and a link the user clicks opens in the browser instead.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    BOOL mainFrame = action.targetFrame.isMainFrame;
    NSURL *expected = self.baseURL ?: [NSURL URLWithString:@"about:blank"];
    if (mainFrame && action.navigationType == WKNavigationTypeOther && self.loadsPending &&
        [WithoutFragment(url) isEqualToString:WithoutFragment(expected)]) {
        self.loadsPending--;
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    if (mainFrame && [url.absoluteString containsString:@"#"] && action.navigationType == WKNavigationTypeLinkActivated &&
        [WithoutFragment(url) isEqualToString:WithoutFragment(webView.URL ?: expected)]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (action.navigationType == WKNavigationTypeLinkActivated &&
        ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"mailto"])) {
        if (self.openLink) self.openLink(url);
    }
    decisionHandler(WKNavigationActionPolicyCancel);
}

@end

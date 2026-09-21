// The Markdown preview: cmark renders the document (CMARK_OPT_UNSAFE keeps
// the raw HTML Markdown is allowed to carry, and what the table pre-pass
// makes), a WKWebView shows it with JavaScript off, and the panel re-renders,
// debounced, whenever the editor's chrome says something changed - which
// typing does. Relative image paths resolve against the document's folder.
#import "MarkdownPanel.h"
#import "EditorController.h"
#import "DockingManager.h"
#import "PluginHost.h"
#import "ScintillaView.h"
#import <WebKit/WebKit.h>
#import "cmark.h"

@interface MarkdownPanel ()
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic) WKWebView *webView;
@property (nonatomic, copy) NSString *lastHTML;
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
        _webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 500) configuration:config];
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
    NSURL *base = folder.length ? [NSURL fileURLWithPath:folder isDirectory:YES] : nil;
    [self.webView loadHTMLString:page baseURL:base];
}

@end

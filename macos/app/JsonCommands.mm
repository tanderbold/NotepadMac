#import "JsonCommands.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"

@implementation NppJsonError
@end

@implementation EditorController (JsonCommands)

#pragma mark - Parsing

+ (NppJsonError *)validateJSON:(NSString *)text {
    NppJsonError *error = [[NppJsonError alloc] init];
    error.line = error.column = error.offset = -1;

    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) { error.message = @"The text is not valid UTF-8."; return error; }

    NSError *parseError = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                options:NSJSONReadingFragmentsAllowed
                                                  error:&parseError];
    if (parsed) return nil;

    error.message = parseError.localizedDescription ?: @"Invalid JSON.";
    NSString *detail = parseError.userInfo[@"NSDebugDescription"];
    if (detail.length) error.message = detail;

    // Foundation gives the position as a byte offset in its own key. Parsing it
    // out of the description instead would depend on the wording, which differs
    // between releases and is localised.
    NSNumber *index = parseError.userInfo[@"NSJSONSerializationErrorIndex"];
    if (index) {
        NSInteger byteOffset = MAX((NSInteger)0, MIN(index.integerValue, (NSInteger)data.length));
        NSString *before = [[NSString alloc] initWithData:
            [data subdataWithRange:NSMakeRange(0, (NSUInteger)byteOffset)]
                                                encoding:NSUTF8StringEncoding] ?: @"";
        NSArray *lines = [before componentsSeparatedByString:@"\n"];
        error.offset = (NSInteger)before.length;
        error.line = (NSInteger)lines.count - 1;
        error.column = (NSInteger)[lines.lastObject length];
    }
    return error;
}

/// NSJSONSerialization drops object key order, so sorting is the only ordering
/// it can guarantee; unsorted output keeps whatever order it produces.
+ (NSString *)formatJSON:(NSString *)text indent:(NSInteger)spaces sorted:(BOOL)sorted {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                options:NSJSONReadingFragmentsAllowed error:NULL];
    if (!parsed) return nil;

    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted | NSJSONWritingFragmentsAllowed;
    if (sorted) options |= NSJSONWritingSortedKeys;
    NSData *out = [NSJSONSerialization dataWithJSONObject:parsed options:options error:NULL];
    if (!out) return nil;

    NSString *pretty = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    // Foundation always indents with two spaces; re-indent when asked otherwise.
    if (spaces != 2 && spaces > 0) {
        NSMutableArray *relaid = [NSMutableArray array];
        for (NSString *line in [pretty componentsSeparatedByString:@"\n"]) {
            NSUInteger lead = 0;
            while (lead < line.length && [line characterAtIndex:lead] == ' ') lead++;
            NSUInteger depth = lead / 2;
            [relaid addObject:[[@"" stringByPaddingToLength:depth * (NSUInteger)spaces
                                                 withString:@" " startingAtIndex:0]
                               stringByAppendingString:[line substringFromIndex:lead]]];
        }
        pretty = [relaid componentsJoinedByString:@"\n"];
    }
    // Escaped slashes are correct but unreadable, and upstream does not add them.
    return [pretty stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
}

+ (NSString *)compactJSON:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                options:NSJSONReadingFragmentsAllowed error:NULL];
    if (!parsed) return nil;
    NSData *out = [NSJSONSerialization dataWithJSONObject:parsed
                                                 options:NSJSONWritingFragmentsAllowed error:NULL];
    if (!out) return nil;
    return [[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding]
            stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
}

#pragma mark - Commands

- (BOOL)replaceDocumentWithJSON:(NSString *)json {
    if (!json) { NppBeep(); return NO; }
    ScintillaView *sci = self.sci;
    long caretLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setString:json];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOLINE
           wParam:(uptr_t)MIN(caretLine, [sci message:SCI_GETLINECOUNT] - 1) lParam:0];
    [self refreshChrome];
    return YES;
}

- (BOOL)formatJSONDocument {
    return [self replaceDocumentWithJSON:
        [EditorController formatJSON:([self.sci string] ?: @"")
                              indent:[NppPreferences shared].jsonIndent sorted:NO]];
}

- (BOOL)sortJSONDocument {
    return [self replaceDocumentWithJSON:
        [EditorController formatJSON:([self.sci string] ?: @"")
                              indent:[NppPreferences shared].jsonIndent sorted:YES]];
}

- (BOOL)compactJSONDocument {
    return [self replaceDocumentWithJSON:
        [EditorController compactJSON:([self.sci string] ?: @"")]];
}

- (NppJsonError *)validateJSONDocument {
    NppJsonError *error = [EditorController validateJSON:([self.sci string] ?: @"")];
    if (error && error.line >= 0) {
        [self.sci message:SCI_GOTOLINE wParam:(uptr_t)error.line lParam:0];
        [self refreshChrome];
    }
    return error;
}

#pragma mark - Tree

static void FlattenJSON(id node, NSString *path, NSMutableArray *out) {
    if ([node isKindOfClass:[NSDictionary class]]) {
        [out addObject:@{@"path": path.length ? path : @"{}",
                         @"value": [NSString stringWithFormat:@"{%lu}",
                                    (unsigned long)[node count]]}];
        for (NSString *key in [[node allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            FlattenJSON(node[key], path.length ? [NSString stringWithFormat:@"%@.%@", path, key] : key,
                        out);
        }
    } else if ([node isKindOfClass:[NSArray class]]) {
        [out addObject:@{@"path": path.length ? path : @"[]",
                         @"value": [NSString stringWithFormat:@"[%lu]",
                                    (unsigned long)[node count]]}];
        NSUInteger i = 0;
        for (id child in node) {
            FlattenJSON(child, [NSString stringWithFormat:@"%@[%lu]", path, (unsigned long)i], out);
            i++;
        }
    } else {
        NSString *value = [node isKindOfClass:[NSNull class]] ? @"null"
                        : [node isKindOfClass:[NSString class]]
                              ? [NSString stringWithFormat:@"\"%@\"", node]
                              : [node description];
        [out addObject:@{@"path": path, @"value": value}];
    }
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)jsonTree {
    NSData *data = [([self.sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return @[];
    id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                options:NSJSONReadingFragmentsAllowed error:NULL];
    if (!parsed) return @[];
    NSMutableArray *out = [NSMutableArray array];
    FlattenJSON(parsed, @"", out);
    return out;
}

@end

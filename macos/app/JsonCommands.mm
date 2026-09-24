#import "JsonCommands.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

@implementation NppJsonError
@end

@implementation EditorController (JsonCommands)

#pragma mark - Parsing

namespace {

/// A JSON value as the document has it: members in their order, numbers and
/// literals as written. NSJSONSerialization loses the order (a dictionary), turns
/// true into 1, and accepts what RFC 8259 does not (a trailing comma), so Format,
/// Compact and the tree go through this instead, as JSON Viewer's RapidJSON does.
struct JsonNode {
    enum Kind { Object, Array, String, Number, Literal } kind = Literal;
    std::string text;                                        // String: decoded UTF-8; Number/Literal: as written
    std::vector<std::pair<std::string, JsonNode>> members;   // Object
    std::vector<JsonNode> items;                             // Array
};

/// Recursive descent over UTF-8, strict RFC 8259 (top level: any value).
struct JsonParser {
    const char *start, *p, *end;
    std::string error;
    size_t errorAt = 0;

    bool fail(const char *why) {
        if (error.empty()) { error = why; errorAt = (size_t)(p - start); }
        return false;
    }
    void blanks() { while (p < end && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')) ++p; }
    static int hex(char c) {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    }
    static void utf8(std::string &out, uint32_t cp) {
        if (cp < 0x80) out += (char)cp;
        else if (cp < 0x800) { out += (char)(0xC0 | (cp >> 6)); out += (char)(0x80 | (cp & 0x3F)); }
        else if (cp < 0x10000) { out += (char)(0xE0 | (cp >> 12)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
        else { out += (char)(0xF0 | (cp >> 18)); out += (char)(0x80 | ((cp >> 12) & 0x3F)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
    }
    bool unicodeEscape(uint32_t &cp) {
        if (end - p < 4) return fail("Invalid \\u escape.");
        cp = 0;
        for (int i = 0; i < 4; ++i) {
            int h = hex(p[i]);
            if (h < 0) return fail("Invalid \\u escape.");
            cp = cp * 16 + (uint32_t)h;
        }
        p += 4;
        return true;
    }
    bool string(std::string &out) {
        ++p;   // the opening quote
        while (true) {
            if (p >= end) return fail("Unterminated string.");
            unsigned char c = (unsigned char)*p;
            if (c == '"') { ++p; return true; }
            if (c < 0x20) return fail("Control character in a string.");
            if (c != '\\') { out += (char)c; ++p; continue; }
            if (++p >= end) return fail("Unterminated string.");
            char e = *p++;
            switch (e) {
                case '"': out += '"'; break;
                case '\\': out += '\\'; break;
                case '/': out += '/'; break;
                case 'b': out += '\b'; break;
                case 'f': out += '\f'; break;
                case 'n': out += '\n'; break;
                case 'r': out += '\r'; break;
                case 't': out += '\t'; break;
                case 'u': {
                    uint32_t cp;
                    if (!unicodeEscape(cp)) return false;
                    if (cp >= 0xD800 && cp <= 0xDBFF && end - p >= 6 && p[0] == '\\' && p[1] == 'u') {
                        const char *save = p;
                        p += 2;
                        uint32_t low;
                        if (!unicodeEscape(low)) return false;
                        if (low >= 0xDC00 && low <= 0xDFFF) cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                        else p = save;
                    }
                    utf8(out, (cp >= 0xD800 && cp <= 0xDFFF) ? 0xFFFD : cp);   // a lone surrogate
                    break;
                }
                default: --p; return fail("Invalid escape in a string.");
            }
        }
    }
    bool number(JsonNode &n) {
        const char *b = p;
        if (p < end && *p == '-') ++p;
        if (p < end && *p == '0') ++p;
        else if (p < end && *p >= '1' && *p <= '9') { while (p < end && *p >= '0' && *p <= '9') ++p; }
        else return fail("Invalid number.");
        if (p < end && *p == '.') {
            ++p;
            if (!(p < end && *p >= '0' && *p <= '9')) return fail("Invalid number.");
            while (p < end && *p >= '0' && *p <= '9') ++p;
        }
        if (p < end && (*p == 'e' || *p == 'E')) {
            ++p;
            if (p < end && (*p == '+' || *p == '-')) ++p;
            if (!(p < end && *p >= '0' && *p <= '9')) return fail("Invalid number.");
            while (p < end && *p >= '0' && *p <= '9') ++p;
        }
        n.kind = JsonNode::Number;
        n.text.assign(b, (size_t)(p - b));
        return true;
    }
    bool literal(JsonNode &n, const char *word) {
        size_t len = strlen(word);
        if ((size_t)(end - p) < len || strncmp(p, word, len) != 0) return fail("Invalid value.");
        n.kind = JsonNode::Literal;
        n.text = word;
        p += len;
        return true;
    }
    bool value(JsonNode &n, int depth) {
        if (depth > 512) return fail("Too deeply nested.");
        blanks();
        if (p >= end) return fail("Unexpected end of the document.");
        char c = *p;
        if (c == '{') {
            n.kind = JsonNode::Object;
            ++p; blanks();
            if (p < end && *p == '}') { ++p; return true; }
            while (true) {
                blanks();
                if (p >= end || *p != '"') return fail(n.members.empty() ? "Expected a member name in double quotes."
                                                                          : "A comma must be followed by a member (no trailing comma).");
                std::pair<std::string, JsonNode> member;
                if (!string(member.first)) return false;
                blanks();
                if (p >= end || *p != ':') return fail("Expected ':' after a member name.");
                ++p;
                if (!value(member.second, depth + 1)) return false;
                n.members.push_back(std::move(member));
                blanks();
                if (p < end && *p == ',') { ++p; continue; }
                if (p < end && *p == '}') { ++p; return true; }
                return fail("Expected ',' or '}'.");
            }
        }
        if (c == '[') {
            n.kind = JsonNode::Array;
            ++p; blanks();
            if (p < end && *p == ']') { ++p; return true; }
            while (true) {
                blanks();
                if (p < end && *p == ']') return fail("A comma must be followed by a value (no trailing comma).");
                JsonNode item;
                if (!value(item, depth + 1)) return false;
                n.items.push_back(std::move(item));
                blanks();
                if (p < end && *p == ',') { ++p; continue; }
                if (p < end && *p == ']') { ++p; return true; }
                return fail("Expected ',' or ']'.");
            }
        }
        if (c == '"') { n.kind = JsonNode::String; return string(n.text); }
        if (c == '-' || (c >= '0' && c <= '9')) return number(n);
        if (c == 't') return literal(n, "true");
        if (c == 'f') return literal(n, "false");
        if (c == 'n') return literal(n, "null");
        return fail("Invalid value.");
    }
    bool document(JsonNode &n) {
        if (!value(n, 0)) return false;
        blanks();
        if (p != end) return fail("Unexpected text after the JSON value.");
        return true;
    }
};

void WriteJsonString(const std::string &s, std::string &out) {
    out += '"';
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) { char buf[8]; snprintf(buf, sizeof buf, "\\u%04x", c); out += buf; }
                else out += (char)c;   // "/" and non-ASCII as they are, as JSON Viewer writes them
        }
    }
    out += '"';
}

/// Keys in the order NSJSONWritingSortedKeys and the tree have always used (compare:).
std::vector<const std::pair<std::string, JsonNode> *> MembersSorted(const JsonNode &n) {
    std::vector<const std::pair<std::string, JsonNode> *> v;
    for (auto &m : n.members) v.push_back(&m);
    std::stable_sort(v.begin(), v.end(), [](auto *a, auto *b) {
        return [@(a->first.c_str()) compare:@(b->first.c_str())] == NSOrderedAscending;
    });
    return v;
}

/// JSON Viewer's layout (RapidJSON PrettyWriter): "key": value, one member or item a line;
/// spaces < 0 writes everything on one line.
void WriteJson(const JsonNode &n, std::string &out, int spaces, int level, bool sorted) {
    auto newline = [&](int lvl) { if (spaces >= 0) { out += '\n'; out.append((size_t)(lvl * spaces), ' '); } };
    switch (n.kind) {
        case JsonNode::Object: {
            if (n.members.empty()) { out += "{}"; break; }
            out += '{';
            std::vector<const std::pair<std::string, JsonNode> *> order;
            if (sorted) order = MembersSorted(n); else for (auto &m : n.members) order.push_back(&m);
            for (size_t i = 0; i < order.size(); ++i) {
                if (i) out += ',';
                newline(level + 1);
                WriteJsonString(order[i]->first, out);
                out += spaces >= 0 ? ": " : ":";
                WriteJson(order[i]->second, out, spaces, level + 1, sorted);
            }
            newline(level);
            out += '}';
            break;
        }
        case JsonNode::Array: {
            if (n.items.empty()) { out += "[]"; break; }
            out += '[';
            for (size_t i = 0; i < n.items.size(); ++i) {
                if (i) out += ',';
                newline(level + 1);
                WriteJson(n.items[i], out, spaces, level + 1, sorted);
            }
            newline(level);
            out += ']';
            break;
        }
        case JsonNode::String: WriteJsonString(n.text, out); break;
        default: out += n.text; break;
    }
}

bool ParseJson(NSString *text, JsonNode &root, std::string *why = nullptr, size_t *at = nullptr) {
    const char *utf = text.UTF8String;
    if (!utf) return false;
    JsonParser parser{utf, utf, utf + strlen(utf)};
    bool ok = parser.document(root);
    if (!ok && why) *why = parser.error;
    if (!ok && at) *at = parser.errorAt;
    return ok;
}

}  // namespace

static void PlaceJsonError(NppJsonError *error, NSData *data, NSInteger byteOffset) {
    byteOffset = MAX((NSInteger)0, MIN(byteOffset, (NSInteger)data.length));
    NSString *before = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, (NSUInteger)byteOffset)]
                                             encoding:NSUTF8StringEncoding] ?: @"";
    NSArray *lines = [before componentsSeparatedByString:@"\n"];
    error.offset = (NSInteger)before.length;
    error.line = (NSInteger)lines.count - 1;
    error.column = (NSInteger)[lines.lastObject length];
}

+ (NppJsonError *)validateJSON:(NSString *)text {
    NppJsonError *error = [[NppJsonError alloc] init];
    error.line = error.column = error.offset = -1;

    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) { error.message = @"The text is not valid UTF-8."; return error; }

    NSError *parseError = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                options:NSJSONReadingFragmentsAllowed
                                                  error:&parseError];
    if (!parsed) {
        error.message = parseError.localizedDescription ?: @"Invalid JSON.";
        NSString *detail = parseError.userInfo[@"NSDebugDescription"];
        if (detail.length) error.message = detail;
        // Foundation gives the position as a byte offset in its own key. Parsing it
        // out of the description instead would depend on the wording, which differs
        // between releases and is localised.
        NSNumber *index = parseError.userInfo[@"NSJSONSerializationErrorIndex"];
        if (index) PlaceJsonError(error, data, index.integerValue);
        return error;
    }
    // What Foundation lets through and RFC 8259 does not - a trailing comma above all
    // (JSON Viewer rejects it too): the strict reading has the last word.
    JsonNode root;
    std::string why;
    size_t at = 0;
    if (ParseJson(text, root, &why, &at)) return nil;
    error.message = @(why.c_str());
    PlaceJsonError(error, data, (NSInteger)at);
    return error;
}

/// JsonViewer's Format: the members in the document's order (Sort Keys is the command that
/// reorders), "key": value, the indent the settings ask for.
+ (NSString *)formatJSON:(NSString *)text indent:(NSInteger)spaces sorted:(BOOL)sorted {
    JsonNode root;
    if (!ParseJson(text, root)) return nil;
    std::string out;
    WriteJson(root, out, spaces > 0 ? (int)spaces : 2, 0, sorted);
    return @(out.c_str());
}

+ (NSString *)compactJSON:(NSString *)text {
    JsonNode root;
    if (!ParseJson(text, root)) return nil;
    std::string out;
    WriteJson(root, out, -1, 0, NO);
    return @(out.c_str());
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

static void FlattenJSON(const JsonNode &node, NSString *path, NSMutableArray *out) {
    if (node.kind == JsonNode::Object) {
        [out addObject:@{@"path": path.length ? path : @"{}",
                         @"value": [NSString stringWithFormat:@"{%lu}", (unsigned long)node.members.size()]}];
        for (auto *m : MembersSorted(node)) {
            NSString *key = @(m->first.c_str());
            FlattenJSON(m->second, path.length ? [NSString stringWithFormat:@"%@.%@", path, key] : key, out);
        }
    } else if (node.kind == JsonNode::Array) {
        [out addObject:@{@"path": path.length ? path : @"[]",
                         @"value": [NSString stringWithFormat:@"[%lu]", (unsigned long)node.items.size()]}];
        for (size_t i = 0; i < node.items.size(); ++i)
            FlattenJSON(node.items[i], [NSString stringWithFormat:@"%@[%lu]", path, (unsigned long)i], out);
    } else {
        // true / false / null and numbers as the document writes them (JSON Viewer's tree).
        NSString *value = node.kind == JsonNode::String ? [NSString stringWithFormat:@"\"%@\"", @(node.text.c_str())]
                                                        : @(node.text.c_str());
        [out addObject:@{@"path": path, @"value": value}];
    }
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)jsonTree {
    JsonNode root;
    if (!ParseJson([self.sci string] ?: @"", root)) return @[];
    NSMutableArray *out = [NSMutableArray array];
    FlattenJSON(root, @"", out);
    return out;
}

@end

#import "HttpRequest.h"
#include <curl/curl.h>
#include <string>
#include <vector>

@implementation NppHttpPair

+ (instancetype)pairWithName:(NSString *)name value:(NSString *)value {
    NppHttpPair *pair = [[NppHttpPair alloc] init];
    pair.name = name ?: @""; pair.value = value ?: @"";
    return pair;
}

+ (NSArray<NppHttpPair *> *)pairsFromText:(NSString *)text separator:(NSString *)separator {
    NSMutableArray<NppHttpPair *> *pairs = [NSMutableArray array];
    NSCharacterSet *blank = [NSCharacterSet whitespaceCharacterSet];
    for (NSString *raw in [text ?: @"" componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:blank];
        if (!line.length || [line hasPrefix:@"#"]) continue;
        NSRange at = [line rangeOfString:separator];
        if (at.location == NSNotFound) { [pairs addObject:[NppHttpPair pairWithName:line value:@""]]; continue; }
        [pairs addObject:[NppHttpPair pairWithName:[[line substringToIndex:at.location] stringByTrimmingCharactersInSet:blank]
                                             value:[[line substringFromIndex:NSMaxRange(at)] stringByTrimmingCharactersInSet:blank]]];
    }
    return pairs;
}

+ (NSString *)textFromPairs:(NSArray<NppHttpPair *> *)pairs separator:(NSString *)separator {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSString *between = [separator isEqualToString:@":"] ? @": " : separator;
    for (NppHttpPair *pair in pairs) [lines addObject:[NSString stringWithFormat:@"%@%@%@", pair.name, between, pair.value]];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@: %@", self.name, self.value]; }

@end

#pragma mark - The request

/// What may stand in a query's name or value as it is; everything else is written %XX.
static NSString *QueryEncoded(NSString *text) {
    static NSCharacterSet *plain;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [text stringByAddingPercentEncodingWithAllowedCharacters:plain] ?: @"";
}

static NSString *ShellQuoted(NSString *text) {
    return [NSString stringWithFormat:@"'%@'", [text stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

@implementation NppHttpRequest

- (instancetype)init {
    if ((self = [super init])) {
        _method = @"GET"; _address = @""; _parameters = @[]; _headers = @[];
        _username = @""; _password = @"";
        _followRedirects = YES; _timeout = 30;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    NppHttpRequest *r = [[NppHttpRequest alloc] init];
    r.method = _method; r.address = _address; r.parameters = _parameters; r.headers = _headers; r.body = _body;
    r.username = _username; r.password = _password; r.followRedirects = _followRedirects;
    r.allowInvalidCertificates = _allowInvalidCertificates; r.timeout = _timeout;
    return r;
}

- (NSURL *)url {
    NSString *address = [self.address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!address.length) return nil;
    // An address typed without its scheme is a web address, as it is to curl.
    if ([address rangeOfString:@"://"].location == NSNotFound) address = [@"http://" stringByAppendingString:address];
    NSURLComponents *parts = [NSURLComponents componentsWithString:address];
    if (!parts) {
        // A space or a Cyrillic letter typed as it is: written %XX, what is already written so left alone.
        NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
        [allowed addCharactersInString:@"%#[]@!$&'()*+,;=:/?"];
        parts = [NSURLComponents componentsWithString:[address stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @""];
    }
    NSString *scheme = parts.scheme.lowercaseString;
    if (!parts.host.length || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return nil;
    if (self.parameters.count) {
        NSMutableArray<NSString *> *more = [NSMutableArray array];
        for (NppHttpPair *pair in self.parameters)
            [more addObject:[NSString stringWithFormat:@"%@=%@", QueryEncoded(pair.name), QueryEncoded(pair.value)]];
        NSString *already = parts.percentEncodedQuery;
        parts.percentEncodedQuery = already.length ? [NSString stringWithFormat:@"%@&%@", already, [more componentsJoinedByString:@"&"]]
                                                   : [more componentsJoinedByString:@"&"];
    }
    return parts.URL;
}

- (NSString *)curlCommand {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSString *method = self.method.uppercaseString;
    NSString *first = @"curl";
    if ([method isEqualToString:@"HEAD"]) first = @"curl -I";
    else if (!([method isEqualToString:@"GET"] && !self.body.length) && !([method isEqualToString:@"POST"] && self.body.length))
        first = [NSString stringWithFormat:@"curl -X %@", method];
    [lines addObject:[NSString stringWithFormat:@"%@ %@", first, ShellQuoted(self.url.absoluteString ?: self.address)]];
    for (NppHttpPair *header in self.headers) [lines addObject:[NSString stringWithFormat:@"-H %@", ShellQuoted(header.description)]];
    if (self.username.length) [lines addObject:[NSString stringWithFormat:@"-u %@", ShellQuoted([NSString stringWithFormat:@"%@:%@", self.username, self.password])]];
    if (self.body.length) {
        NSString *text = [[NSString alloc] initWithData:self.body encoding:NSUTF8StringEncoding];
        if (text) [lines addObject:[NSString stringWithFormat:@"--data-raw %@", ShellQuoted(text)]];
    }
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
    if (self.followRedirects) [flags addObject:@"-L"];
    if (self.allowInvalidCertificates) [flags addObject:@"-k"];
    if (self.timeout > 0 && self.timeout != 30) [flags addObject:[NSString stringWithFormat:@"-m %ld", (long)self.timeout]];
    if (flags.count) [lines addObject:[flags componentsJoinedByString:@" "]];
    return [lines componentsJoinedByString:@" \\\n  "];
}

#pragma mark Reading a curl command

/// The words of a command as a POSIX shell would hand them over: quotes taken off, backslashes
/// obeyed, a backslash at a line's end joining it to the next, and bash's $'...' with its escapes -
/// which is how a browser's "Copy as cURL" writes a body with a line break in it.
static NSArray<NSString *> *ShellWords(NSString *command) {
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSMutableString *word = nil;
    NSUInteger n = command.length, i = 0;
    #define WORD() (word ?: (word = [NSMutableString string]))
    while (i < n) {
        unichar c = [command characterAtIndex:i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            if (word) { [words addObject:word]; word = nil; }
            ++i; continue;
        }
        if (c == '\\') {
            if (i + 1 < n && [command characterAtIndex:i + 1] == '\n') { i += 2; continue; }
            if (i + 2 < n && [command characterAtIndex:i + 1] == '\r' && [command characterAtIndex:i + 2] == '\n') { i += 3; continue; }
            if (i + 1 < n) [WORD() appendFormat:@"%C", [command characterAtIndex:i + 1]];
            i += 2; continue;
        }
        if (c == '\'') {
            NSUInteger end = i + 1;
            while (end < n && [command characterAtIndex:end] != '\'') ++end;
            [WORD() appendString:[command substringWithRange:NSMakeRange(i + 1, end - i - 1)]];
            i = end + 1; continue;
        }
        if (c == '"') {
            ++i; (void)WORD();
            while (i < n && [command characterAtIndex:i] != '"') {
                unichar d = [command characterAtIndex:i];
                if (d == '\\' && i + 1 < n) {
                    unichar e = [command characterAtIndex:i + 1];
                    if (e == '\n') { i += 2; continue; }
                    if (e == '"' || e == '\\' || e == '$' || e == '`') { [word appendFormat:@"%C", e]; i += 2; continue; }
                }
                [word appendFormat:@"%C", d]; ++i;
            }
            ++i; continue;
        }
        if (c == '$' && i + 1 < n && [command characterAtIndex:i + 1] == '\'') {
            i += 2; (void)WORD();
            while (i < n && [command characterAtIndex:i] != '\'') {
                unichar d = [command characterAtIndex:i];
                if (d != '\\' || i + 1 >= n) { [word appendFormat:@"%C", d]; ++i; continue; }
                unichar e = [command characterAtIndex:i + 1];
                i += 2;
                NSUInteger digits = e == 'x' ? 2 : e == 'u' ? 4 : 0;
                if (digits) {
                    unsigned value = 0; NSUInteger taken = 0;
                    while (taken < digits && i < n && isxdigit((int)MIN([command characterAtIndex:i], (unichar)127))) {
                        unichar h = [command characterAtIndex:i];
                        value = value * 16 + (unsigned)(h <= '9' ? h - '0' : (h | 0x20) - 'a' + 10); ++i; ++taken;
                    }
                    [word appendFormat:@"%C", (unichar)value];
                    continue;
                }
                unichar plain = e == 'n' ? '\n' : e == 't' ? '\t' : e == 'r' ? '\r' : e == 'a' ? 7 : e == 'b' ? 8 : e == 'e' ? 27 : e;
                [word appendFormat:@"%C", plain];
            }
            ++i; continue;
        }
        [WORD() appendFormat:@"%C", c];
        ++i;
    }
    #undef WORD
    if (word) [words addObject:word];
    return words;
}

+ (instancetype)requestFromCurlCommand:(NSString *)command error:(NSString **)error {
    NSArray<NSString *> *words = ShellWords(command ?: @"");
    if (!words.count || ![words[0].lastPathComponent.lowercaseString hasPrefix:@"curl"]) {
        if (error) *error = @"This is not a curl command.";
        return nil;
    }
    NppHttpRequest *request = [[NppHttpRequest alloc] init];
    request.followRedirects = NO;                  // curl follows none unless told to
    NSMutableArray<NppHttpPair *> *headers = [NSMutableArray array];
    NSMutableArray<NSString *> *data = [NSMutableArray array];

    // Options that take a value, by their long names; the short ones are given theirs below.
    NSDictionary<NSString *, NSString *> *shortToLong = @{
        @"X": @"request", @"H": @"header", @"d": @"data", @"u": @"user", @"A": @"user-agent", @"e": @"referer", @"b": @"cookie",
        @"m": @"max-time", @"o": @"output", @"w": @"write-out", @"x": @"proxy", @"c": @"cookie-jar", @"F": @"form", @"T": @"upload-file",
        @"E": @"cert", @"r": @"range", @"U": @"proxy-user", @"K": @"config", @"D": @"dump-header", @"y": @"speed-time", @"Y": @"speed-limit",
        @"z": @"time-cond", @"C": @"continue-at", @"t": @"telnet-option", @"Q": @"quote", @"P": @"ftp-port", @"h": @"help"};
    NSSet<NSString *> *valued = [NSSet setWithArray:[shortToLong.allValues arrayByAddingObjectsFromArray:@[
        @"data-raw", @"data-binary", @"data-ascii", @"data-urlencode", @"json", @"url", @"connect-timeout", @"retry", @"retry-delay",
        @"retry-max-time", @"cacert", @"capath", @"key", @"resolve", @"connect-to", @"interface", @"proxy-header", @"form-string",
        @"ciphers", @"tls-max", @"oauth2-bearer", @"aws-sigv4", @"unix-socket", @"max-redirs", @"limit-rate", @"keepalive-time",
        @"cert-type", @"key-type", @"pass", @"pinnedpubkey", @"noproxy", @"dns-servers", @"stderr", @"trace", @"trace-ascii", @"variable",
        @"expand-url", @"max-filesize", @"rate", @"request-target", @"socks5", @"socks5-hostname", @"socks4", @"socks4a", @"preproxy"]]];

    __block NSString *failure = nil, *method = nil, *address = nil;
    __block BOOL asQuery = NO, json = NO;
    void (^take)(NSString *, NSString *) = ^(NSString *option, NSString *value) {
        if ([option isEqualToString:@"request"]) method = value.uppercaseString;
        else if ([option isEqualToString:@"header"]) {
            NSRange at = [value rangeOfString:@":"];
            NSCharacterSet *blank = [NSCharacterSet whitespaceCharacterSet];
            if (at.location == NSNotFound) { if ([value hasSuffix:@";"]) [headers addObject:[NppHttpPair pairWithName:[value substringToIndex:value.length - 1] value:@""]]; }
            else [headers addObject:[NppHttpPair pairWithName:[[value substringToIndex:at.location] stringByTrimmingCharactersInSet:blank]
                                                        value:[[value substringFromIndex:at.location + 1] stringByTrimmingCharactersInSet:blank]]];
        }
        else if ([@[@"data", @"data-raw", @"data-binary", @"data-ascii"] containsObject:option]) {
            // (A value that begins with @ names a file to curl; it is not read here, where a command is only pasted.)
            if ([value hasPrefix:@"@"] && ![option isEqualToString:@"data-raw"]) failure = @"The command reads its data from a file, which is not done here.";
            [data addObject:value];
        }
        else if ([option isEqualToString:@"data-urlencode"]) {
            NSRange at = [value rangeOfString:@"="];
            if (at.location == NSNotFound) [data addObject:QueryEncoded(value)];
            else if (at.location == 0) [data addObject:QueryEncoded([value substringFromIndex:1])];
            else [data addObject:[NSString stringWithFormat:@"%@=%@", [value substringToIndex:at.location], QueryEncoded([value substringFromIndex:at.location + 1])]];
        }
        else if ([option isEqualToString:@"json"]) { [data addObject:value]; json = YES; }
        else if ([option isEqualToString:@"user"]) {
            NSRange at = [value rangeOfString:@":"];
            request.username = at.location == NSNotFound ? value : [value substringToIndex:at.location];
            request.password = at.location == NSNotFound ? @"" : [value substringFromIndex:at.location + 1];
        }
        else if ([option isEqualToString:@"user-agent"]) [headers addObject:[NppHttpPair pairWithName:@"User-Agent" value:value]];
        else if ([option isEqualToString:@"referer"]) [headers addObject:[NppHttpPair pairWithName:@"Referer" value:value]];
        else if ([option isEqualToString:@"cookie"]) { if ([value containsString:@"="]) [headers addObject:[NppHttpPair pairWithName:@"Cookie" value:value]]; }
        else if ([option isEqualToString:@"oauth2-bearer"]) [headers addObject:[NppHttpPair pairWithName:@"Authorization" value:[@"Bearer " stringByAppendingString:value]]];
        else if ([option isEqualToString:@"max-time"]) request.timeout = MAX(0, value.doubleValue);
        else if ([option isEqualToString:@"url"]) address = address ?: value;
        else if ([option isEqualToString:@"form"] || [option isEqualToString:@"form-string"] || [option isEqualToString:@"upload-file"])
            failure = @"Forms and uploads of files are not read from a command.";
        // Everything else that takes a value - an output file, a proxy, a certificate - is passed over with it.
    };
    void (^flag)(NSString *) = ^(NSString *option) {
        if ([option isEqualToString:@"insecure"]) request.allowInvalidCertificates = YES;
        else if ([option isEqualToString:@"location"] || [option isEqualToString:@"location-trusted"]) request.followRedirects = YES;
        else if ([option isEqualToString:@"head"]) method = @"HEAD";
        else if ([option isEqualToString:@"get"]) asQuery = YES;
    };
    NSDictionary<NSString *, NSString *> *shortFlags = @{@"k": @"insecure", @"L": @"location", @"I": @"head", @"G": @"get"};

    for (NSUInteger i = 1; i < words.count; ++i) {
        NSString *word = words[i];
        if ([word hasPrefix:@"--"] && word.length > 2) {
            NSString *option = [word substringFromIndex:2], *value = nil;
            NSRange equals = [option rangeOfString:@"="];
            if (equals.location != NSNotFound) { value = [option substringFromIndex:equals.location + 1]; option = [option substringToIndex:equals.location]; }
            if ([valued containsObject:option]) {
                if (!value && i + 1 < words.count) value = words[++i];
                take(option, value ?: @"");
            } else flag(option);
        } else if ([word hasPrefix:@"-"] && word.length > 1) {
            // Short options may be run together, and one that takes a value takes the rest of the word or the next one.
            for (NSUInteger k = 1; k < word.length; ++k) {
                NSString *letter = [word substringWithRange:NSMakeRange(k, 1)];
                NSString *longName = shortToLong[letter];
                if (longName) {
                    NSString *value = k + 1 < word.length ? [word substringFromIndex:k + 1] : (i + 1 < words.count ? words[++i] : @"");
                    take(longName, value);
                    break;
                }
                if (shortFlags[letter]) flag(shortFlags[letter]);
            }
        } else if (!address) address = word;
    }
    if (failure) { if (error) *error = failure; return nil; }
    if (!address.length) { if (error) *error = @"The command has no address."; return nil; }

    request.address = address;
    if (json) {
        BOOL (^has)(NSString *) = ^BOOL(NSString *name) {
            for (NppHttpPair *h in headers) if ([h.name caseInsensitiveCompare:name] == NSOrderedSame) return YES;
            return NO;
        };
        if (!has(@"Content-Type")) [headers addObject:[NppHttpPair pairWithName:@"Content-Type" value:@"application/json"]];
        if (!has(@"Accept")) [headers addObject:[NppHttpPair pairWithName:@"Accept" value:@"application/json"]];
    }
    NSString *joined = [data componentsJoinedByString:json ? @"" : @"&"];
    if (asQuery && data.count) {
        // -G: what would have been the body goes into the address instead.
        request.address = [address stringByAppendingFormat:@"%@%@", [address containsString:@"?"] ? @"&" : @"?", joined];
    } else if (data.count) {
        request.body = [joined dataUsingEncoding:NSUTF8StringEncoding];
    }
    request.method = method ?: (request.body ? @"POST" : @"GET");
    request.headers = headers;
    if (![request url]) { if (error) *error = @"The command's address is not an http or https address."; return nil; }
    return request;
}

@end

#pragma mark - The answer

@implementation NppHttpResponse

- (instancetype)init {
    if ((self = [super init])) { _statusLine = @""; _headers = @[]; _body = [NSData data]; }
    return self;
}

- (NSString *)valueOfHeader:(NSString *)name {
    for (NppHttpPair *header in self.headers) if ([header.name caseInsensitiveCompare:name] == NSOrderedSame) return header.value;
    return nil;
}

- (NSString *)text {
    if (!self.body.length) return @"";
    NSString *type = [self valueOfHeader:@"Content-Type"] ?: @"";
    NSRange at = [type rangeOfString:@"charset=" options:NSCaseInsensitiveSearch];
    if (at.location != NSNotFound) {
        NSString *name = [[type substringFromIndex:NSMaxRange(at)] componentsSeparatedByString:@";"].firstObject;
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \"'"]];
        CFStringEncoding encoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)name);
        if (encoding != kCFStringEncodingInvalidId) {
            NSString *text = [[NSString alloc] initWithData:self.body encoding:CFStringConvertEncodingToNSStringEncoding(encoding)];
            if (text) return text;
        }
    }
    return [[NSString alloc] initWithData:self.body encoding:NSUTF8StringEncoding];
}

- (NSString *)headerText {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    if (self.statusLine.length) [lines addObject:self.statusLine];
    for (NppHttpPair *header in self.headers) [lines addObject:header.description];
    return [lines componentsJoinedByString:@"\n"];
}

@end

#pragma mark - Sending

namespace {

struct Transfer {
    NSMutableData *body;
    NSMutableArray<NppHttpPair *> *headers;
    NSString *statusLine;
    NSInteger answers;
    BOOL (^cancelled)(void);
};

size_t TakeBody(char *data, size_t size, size_t count, void *context) {
    [((Transfer *)context)->body appendBytes:data length:size * count];
    return size * count;
}

size_t TakeHeader(char *data, size_t size, size_t count, void *context) {
    Transfer *transfer = (Transfer *)context;
    NSString *line = [[NSString alloc] initWithBytes:data length:size * count encoding:NSUTF8StringEncoding]
                  ?: [[NSString alloc] initWithBytes:data length:size * count encoding:NSISOLatin1StringEncoding] ?: @"";
    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([line hasPrefix:@"HTTP/"]) {
        // Each answer on the way - a "100 Continue", a redirect - starts the headers anew: the last one's are kept.
        [transfer->headers removeAllObjects];
        [transfer->body setLength:0];
        transfer->statusLine = line;
        NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
        NSInteger status = parts.count > 1 ? parts[1].integerValue : 0;
        if (status >= 200) transfer->answers++;
    } else if (line.length) {
        NSRange at = [line rangeOfString:@":"];
        if (at.location != NSNotFound)
            [transfer->headers addObject:[NppHttpPair pairWithName:[line substringToIndex:at.location]
                                                             value:[[line substringFromIndex:at.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]]];
    }
    return size * count;
}

int Progress(void *context, curl_off_t, curl_off_t, curl_off_t, curl_off_t) {
    Transfer *transfer = (Transfer *)context;
    return transfer->cancelled && transfer->cancelled() ? 1 : 0;
}

}  // namespace

@implementation NppHttpClient

+ (NppHttpResponse *)send:(NppHttpRequest *)request cancelled:(BOOL (^)(void))cancelled {
    NppHttpResponse *response = [[NppHttpResponse alloc] init];
    NSURL *url = [request url];
    if (!url) { response.error = @"The address is not an http or https address."; return response; }
    static dispatch_once_t once;
    dispatch_once(&once, ^{ curl_global_init(CURL_GLOBAL_DEFAULT); });
    CURL *curl = curl_easy_init();
    if (!curl) { response.error = @"libcurl could not be started."; return response; }

    Transfer transfer = {[NSMutableData data], [NSMutableArray array], @"", 0, cancelled};
    NSString *method = request.method.length ? request.method.uppercaseString : @"GET";
    curl_easy_setopt(curl, CURLOPT_URL, url.absoluteString.UTF8String);
    // Nothing but the web: an address pasted from somewhere is not to read a file or talk to a mail server.
    curl_easy_setopt(curl, CURLOPT_PROTOCOLS, (long)(CURLPROTO_HTTP | CURLPROTO_HTTPS));
    curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS, (long)(CURLPROTO_HTTP | CURLPROTO_HTTPS));
    if ([method isEqualToString:@"HEAD"]) curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
    else if (![method isEqualToString:@"GET"] || request.body.length) curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method.UTF8String);
    if (request.body.length && ![method isEqualToString:@"HEAD"]) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)request.body.length);
        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, (const char *)request.body.bytes);
    }
    struct curl_slist *list = NULL;
    BOOL agentGiven = NO;
    for (NppHttpPair *header in request.headers) {
        if (!header.name.length) continue;
        if ([header.name caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) agentGiven = YES;
        // (libcurl takes "Name;" for a header sent with no value, and "Name:" for one not to be sent at all.)
        NSString *line = header.value.length ? [NSString stringWithFormat:@"%@: %@", header.name, header.value]
                                             : [NSString stringWithFormat:@"%@;", header.name];
        list = curl_slist_append(list, line.UTF8String);
    }
    if (list) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, list);
    if (!agentGiven) {
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
        NSString *agent = [@"NotepadMac/" stringByAppendingString:version];
        curl_easy_setopt(curl, CURLOPT_USERAGENT, agent.UTF8String);
    }
    if (request.username.length) {
        curl_easy_setopt(curl, CURLOPT_HTTPAUTH, (long)CURLAUTH_BASIC);
        curl_easy_setopt(curl, CURLOPT_USERNAME, request.username.UTF8String);
        curl_easy_setopt(curl, CURLOPT_PASSWORD, request.password.UTF8String);
    }
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, request.followRedirects ? 1L : 0L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 20L);
    if (request.allowInvalidCertificates) {
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
    }
    if (request.timeout > 0) curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, (long)(request.timeout * 1000));
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");           // whatever libcurl can unpack, unpacked
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, TakeBody);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &transfer);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, TakeHeader);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, &transfer);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, Progress);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &transfer);
    char failure[CURL_ERROR_SIZE] = "";
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, failure);

    NSDate *started = [NSDate date];
    CURLcode code = curl_easy_perform(curl);
    response.elapsed = -started.timeIntervalSinceNow;
    long status = 0;
    char *final = NULL;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &final);
    if (final) response.finalAddress = @(final);
    if (code != CURLE_OK) {
        response.error = code == CURLE_ABORTED_BY_CALLBACK ? @"Cancelled." : (failure[0] ? @(failure) : @(curl_easy_strerror(code)));
    }
    if (code == CURLE_OK || transfer.answers) {
        response.status = status;
        response.statusLine = transfer.statusLine;
        response.headers = transfer.headers;
        response.body = transfer.body;
        response.redirects = MAX(transfer.answers - 1, 0);
    }
    curl_slist_free_all(list);
    curl_easy_cleanup(curl);
    return response;
}

@end

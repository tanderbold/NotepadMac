#import "UpdateChecker.h"
#import "SettingsCommands.h"

@implementation NppRelease
@end

static NSURL *gOverride;

@implementation NppUpdateChecker

+ (NSArray<NSNumber *> *)numbersIn:(NSString *)version {
    NSMutableArray *out = [NSMutableArray array];
    NSScanner *scan = [NSScanner scannerWithString:version ?: @""];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    while (!scan.atEnd) {
        [scan scanUpToCharactersFromSet:digits intoString:NULL];
        NSInteger n;
        if ([scan scanInteger:&n]) [out addObject:@(n)];
    }
    return out;
}

+ (NSComparisonResult)compareVersion:(NSString *)a to:(NSString *)b {
    NSArray *x = [self numbersIn:a], *y = [self numbersIn:b];
    for (NSUInteger i = 0; i < MAX(x.count, y.count); ++i) {
        NSInteger p = i < x.count ? [x[i] integerValue] : 0, q = i < y.count ? [y[i] integerValue] : 0;
        if (p != q) return p < q ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

+ (NppRelease *)releaseFromJSON:(NSData *)data {
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSString *tag = json[@"tag_name"];
    if (![tag isKindOfClass:[NSString class]] || !tag.length) return nil;
    NppRelease *r = [NppRelease new];
    r.version = [tag hasPrefix:@"v"] || [tag hasPrefix:@"V"] ? [tag substringFromIndex:1] : tag;
    r.name = [json[@"name"] isKindOfClass:[NSString class]] && [json[@"name"] length] ? json[@"name"] : tag;
    NSString *page = [json[@"html_url"] isKindOfClass:[NSString class]] ? json[@"html_url"] : nil;
    r.pageURL = [NSURL URLWithString:page ?: @""] ?: [self releasesPage];
    r.notes = [json[@"body"] isKindOfClass:[NSString class]] ? json[@"body"] : @"";
    return r;
}

+ (NSURL *)releasesPage {
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@/releases",
                                 [NppPreferences shared].updateRepository]];
}

+ (NSDictionary *)proxyDictionaryFor:(NSString *)proxy {
    NSString *p = [proxy stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // "http://host:port" is taken too, as WinGUp's proxy field does.
    NSRange scheme = [p rangeOfString:@"://"];
    if (scheme.location != NSNotFound) p = [p substringFromIndex:NSMaxRange(scheme)];
    if ([p hasSuffix:@"/"]) p = [p substringToIndex:p.length - 1];
    if (!p.length) return @{};
    NSRange colon = [p rangeOfString:@":" options:NSBackwardsSearch];
    NSString *host = colon.location == NSNotFound ? p : [p substringToIndex:colon.location];
    NSInteger port = colon.location == NSNotFound ? 80 : [p substringFromIndex:NSMaxRange(colon)].integerValue;
    if (!host.length || port <= 0) return @{};
    return @{@"HTTPEnable": @YES, @"HTTPProxy": host, @"HTTPPort": @(port),
             @"HTTPSEnable": @YES, @"HTTPSProxy": host, @"HTTPSPort": @(port)};
}

+ (NSDateFormatter *)dayFormat {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    f.dateFormat = @"yyyyMMdd";
    return f;
}

+ (BOOL)isDueOn:(NSDate *)day next:(NSString *)next {
    if (next.length != 8) return YES;
    return [[[self dayFormat] stringFromDate:day] compare:next] != NSOrderedAscending;
}

+ (NSString *)dateString:(NSDate *)day plusDays:(NSInteger)days {
    NSDate *later = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]
                        dateByAddingUnit:NSCalendarUnitDay value:ABS(days) toDate:day options:0];
    return [[self dayFormat] stringFromDate:later ?: day];
}

+ (NSString *)currentVersion {
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    return info[@"NppUpstreamVersion"] ?: info[@"CFBundleShortVersionString"] ?: @"0";
}

+ (NSURL *)latestReleaseURLOverride { return gOverride; }
+ (void)setLatestReleaseURLOverride:(NSURL *)url { gOverride = [url copy]; }

+ (NSURL *)latestReleaseURL {
    if (gOverride) return gOverride;
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest",
                                 [NppPreferences shared].updateRepository]];
}

+ (void)fetchLatest:(void (^)(NppRelease *, NSError *))done {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 20;
    NSString *proxy = [[NSUserDefaults standardUserDefaults] stringForKey:@"NppMacUpdaterProxy"] ?: @"";
    NSDictionary *proxies = [self proxyDictionaryFor:proxy];
    if (proxies.count) config.connectionProxyDictionary = proxies;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self latestReleaseURL]];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"NotepadMac-updater" forHTTPHeaderField:@"User-Agent"];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NppRelease *release = error ? nil : [self releaseFromJSON:data];
        NSError *failure = error;
        if (!release && !failure) {
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            failure = [NSError errorWithDomain:@"NppUpdate" code:status
                                      userInfo:@{NSLocalizedDescriptionKey: status == 404
                                          ? @"No release has been published yet."
                                          : @"The release information could not be read."}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(release, failure); });
        [session finishTasksAndInvalidate];
    }] resume];
}

@end

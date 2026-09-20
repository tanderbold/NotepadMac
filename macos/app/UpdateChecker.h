// Checking for a newer release, as Notepad++'s WinGUp does, against the
// port's GitHub Releases.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppRelease : NSObject
@property (nonatomic, copy) NSString *version;   // "8.9.8", without the leading v
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSURL *pageURL;
@property (nonatomic, copy) NSString *notes;
@end

@interface NppUpdateChecker : NSObject
/// -1, 0 or 1 as a is older, the same or newer than b; the numbers in
/// "v8.9.8", "8.9.8-mac2" and "8.10" are compared one by one.
+ (NSComparisonResult)compareVersion:(NSString *)a to:(NSString *)b;
/// The release a GitHub "releases/latest" answer describes, or nil.
+ (nullable NppRelease *)releaseFromJSON:(NSData *)data;
/// The session proxy settings for "host:port" (empty: none).
+ (NSDictionary *)proxyDictionaryFor:(NSString *)proxy;
/// Whether the periodic check is due on the given day ("yyyyMMdd" compare).
+ (BOOL)isDueOn:(NSDate *)day next:(nullable NSString *)next;
/// "yyyyMMdd" for the day `days` after `day`.
+ (NSString *)dateString:(NSDate *)day plusDays:(NSInteger)days;
/// This build's version: upstream's, then the port's own, as "8.9.8".
+ (NSString *)currentVersion;
/// Where the latest release is asked for; tests point it at a file.
@property (class, nonatomic, copy, nullable) NSURL *latestReleaseURLOverride;
+ (NSURL *)latestReleaseURL;

/// Fetches the latest release through the configured proxy; the block runs
/// on the main queue with the release (nil and an error when it failed).
+ (void)fetchLatest:(void (^)(NppRelease *_Nullable release, NSError *_Nullable error))done;
@end

NS_ASSUME_NONNULL_END

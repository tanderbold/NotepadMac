// A set of numbers as a selection holds them: "3, 1, 2", "3 1 2", "3; 1; 2",
// one per line, or the pieces of a column selection. Its sum, average,
// minimum, maximum and count, and the same text with the numbers sorted,
// each keeping its own spelling and every separator staying where it was.
//
// Separators are blanks, line breaks, commas and semicolons, one comma or
// semicolon between two numbers at most. A comma is a decimal comma instead
// when blanks or semicolons separate the numbers and every one of them reads
// as digits with at most one comma inside ("1,5 2,25", "1,5; 2"): then
// results are written with a comma too. Arithmetic is decimal, so 0.1 + 0.2
// is 0.3.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppNumberSet : NSObject

/// The set in these pieces of text (a column selection has several); nil
/// unless they hold at least two numbers and nothing but numbers and
/// separators.
+ (nullable instancetype)setFromPieces:(NSArray<NSString *> *)pieces;

@property (nonatomic, readonly) NSUInteger count;
/// Written in the input's decimal style; the average to ten decimal places at most.
@property (nonatomic, readonly) NSString *sum;
@property (nonatomic, readonly) NSString *average;
@property (nonatomic, readonly) NSString *minimum;
@property (nonatomic, readonly) NSString *maximum;

/// The pieces again with the numbers in order (equal ones keep theirs).
- (NSArray<NSString *> *)piecesSortedAscending:(BOOL)ascending;

@end

NS_ASSUME_NONNULL_END

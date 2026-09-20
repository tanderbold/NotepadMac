// The trained part of working out a language from a piece of text.
//
// train-language-model.py fits the weights offline, over the Linguist samples,
// Rosetta Code, Lexilla's lexer examples and this repository's own files, and
// writes them next to the application. Nothing is trained here and nothing is
// downloaded: this reads the file and adds up what it says.
//
// The features are computed here exactly as the trainer computes them - the
// same bytes, the same keys - and the trainer can read its own file back and
// answer, so the two can be checked against each other.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// What the model makes of a piece of text: a language and how likely it is,
/// as a share of the whole, from zero to one.
@interface NppLanguageGuess : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) double confidence;
@property (nonatomic) double score;
@end

/// The most languages worth offering as a choice. Past this the text has not
/// narrowed anything down, and nothing is offered.
extern const NSUInteger NppMostLanguagesToOffer;
/// How many languages are offered when one alone is not sure enough.
extern const NSUInteger NppShortListLength;

@interface NppLanguageModel : NSObject

/// The model shipped with the application, or nil when the file is missing or
/// unreadable. Loaded once; everything after that is a lookup.
+ (nullable instancetype)sharedModel;

/// Reads a model from a file. Returns nil unless the file is one of ours and
/// its parts are the length its header says they are.
+ (nullable instancetype)modelWithContentsOfFile:(NSString *)path;

/// The languages the model knows. A language absent from this has no weights.
@property (nonatomic, readonly) NSArray<NSString *> *languageNames;

/// The level a language's likelihood has to reach to be offered, as the
/// trainer chose it on held-back fragments.
@property (nonatomic, readonly) double coverage;
/// How sure one language must be to be offered alone (at least `coverage`).
@property (nonatomic, readonly) double singleLevel;

/// Every language the model knows, most likely first, with how likely each is.
/// Empty when there is too little text to say anything, or when the text has
/// nothing in it the model has ever seen.
- (NSArray<NppLanguageGuess *> *)guessesForText:(NSString *)text;

/// The languages to offer for the text: those whose likelihood reaches the
/// level, most likely first. One name means the text is characteristic enough
/// to apply it outright. An empty array means either none reached it or more
/// than NppMostLanguagesToOffer did, so the text narrows nothing down. nil
/// means the model could not judge the text at all.
- (nullable NSArray<NSString *> *)languagesOfferedForText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END

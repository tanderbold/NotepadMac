// Working out a language from what is inside a file, for the files that carry
// no extension to go by. Notepad++ has nothing of the kind; it is offered here
// as a setting, and only ever consulted when the name says nothing.
#import "LanguageCatalog.h"
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

@interface LanguageCatalog (Detection)

/// The languages the text could be, best first. Empty when the text says too
/// little to narrow anything down, and empty as well when too many languages
/// fit it to be worth offering: a list of everything is no help. Reads only the
/// beginning of long files.
- (NSArray<NppLanguage *> *)languagesMatchingContents:(NSString *)text;

/// The one language the text points at, when it points at exactly one: a
/// shebang line and its like, or a single candidate well clear of the rest.
- (nullable NppLanguage *)languageForContents:(NSString *)text;

/// The most languages worth offering. Past this the content has not narrowed
/// anything down and no language is chosen.
extern const NSUInteger NppMostLanguagesToOffer;

/// What the text says about itself outright: a shebang line, an XML or PHP
/// opening tag, an HTML doctype, an editor modeline, or JSON that parses.
/// These are taken as given; the trained model is only asked without one.
- (nullable NppLanguage *)declaredLanguageInContents:(NSString *)text;

@end

@interface EditorController (LanguageDetection)

/// Works out the language of the document in front from what is in it, for the
/// times its name cannot say: a file with no extension, or a fragment pasted
/// into an empty document. Does nothing when the setting is off, when the name
/// already settled it, or when the user chose a language themselves.
///
/// One candidate is applied outright. Several are returned for the caller to
/// offer; none are returned when the content narrows nothing down.
- (NSArray<NppLanguage *> *)languagesSuggestedForCurrentDocument;

/// Where to put several candidate languages when a file is opened and its name
/// does not settle the question. Set by whoever can ask the user; without it
/// such a file is simply left as text.
@property (nonatomic, copy, nullable) void (^languageChoiceHandler)(NSArray<NppLanguage *> *choices);

/// The same, and when several languages fit it hands them to `chooser` so they
/// can be put to the user. Returns what was applied, if anything.
- (nullable NppLanguage *)detectLanguageOfCurrentDocumentOffering:
    (void (^_Nullable)(NSArray<NppLanguage *> *choices))chooser;

@end

NS_ASSUME_NONNULL_END

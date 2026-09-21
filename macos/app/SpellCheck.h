// DSpellCheck's job, done with the system's spelling engine: misspelled words
// squiggled as you type, suggestions in the context menu, Ignore and Learn.
// In code only comments and strings are checked, as the plugin does it; plain
// text is checked whole. The language is the system's guess or one chosen in
// Plugins > Spell Check > Language.
#import "EditorController.h"

#define NPPMAC_SPELL_INDICATOR 17

NS_ASSUME_NONNULL_BEGIN

@interface EditorController (SpellCheck)

/// A debounced pass over the visible lines; SCN_UPDATEUI calls it.
- (void)scheduleSpellCheck;

/// The pass itself, at once: clears the visible range's squiggles and puts
/// back those the spelling engine still finds. Off, it clears the document.
- (void)spellCheckNow;

/// Suggestion, Ignore and Learn items for a misspelled word at a position;
/// empty when checking is off or the position carries no squiggle. The
/// context menu puts them on top.
- (NSArray<NSMenuItem *> *)spellingMenuItemsForPosition:(long)position;

@end

NS_ASSUME_NONNULL_END

// The plugin's settings, the part the engine reads: colours, and the compare
// options the port keeps in its own preferences and copies in here.
#pragma once
#include "windows.h"

#define DEFAULT_ADDED_COLOR             0xC6FFC6
#define DEFAULT_REMOVED_COLOR           0xC6C6FF
#define DEFAULT_MOVED_COLOR             0xFFE6CC
#define DEFAULT_CHANGED_COLOR           0x98E7E7
#define DEFAULT_PART_COLOR              0x0683FF
#define DEFAULT_MOVED_PART_COLOR        0xF58742
#define DEFAULT_ADDED_COLOR_DARK        0x055A05
#define DEFAULT_REMOVED_COLOR_DARK      0x16164F
#define DEFAULT_MOVED_COLOR_DARK        0x4F361C
#define DEFAULT_CHANGED_COLOR_DARK      0x145050
#define DEFAULT_PART_COLOR_DARK         0x0683FF
#define DEFAULT_MOVED_PART_COLOR_DARK   0xF58742
#define DEFAULT_PART_TRANSPARENCY       0
#define DEFAULT_CARET_LINE_TRANSPARENCY 0
#define DEFAULT_CHANGED_THRESHOLD       30

struct ColorSettings {
    int added, removed, changed, moved, blank, _default;
    int added_part, removed_part, moved_part;
    int part_transparency, caret_line_transparency;
};

struct UserSettings {
    ColorSettings &colors() { return dark ? colorsDark : colorsLight; }
    const ColorSettings &colors() const { return dark ? colorsDark : colorsLight; }
    bool dark = false;
    ColorSettings colorsLight {DEFAULT_ADDED_COLOR, DEFAULT_REMOVED_COLOR, DEFAULT_CHANGED_COLOR, DEFAULT_MOVED_COLOR, 0xEEEEEE, 0xFFFFFF,
                               DEFAULT_PART_COLOR, DEFAULT_PART_COLOR, DEFAULT_MOVED_PART_COLOR, DEFAULT_PART_TRANSPARENCY, DEFAULT_CARET_LINE_TRANSPARENCY};
    ColorSettings colorsDark  {DEFAULT_ADDED_COLOR_DARK, DEFAULT_REMOVED_COLOR_DARK, DEFAULT_CHANGED_COLOR_DARK, DEFAULT_MOVED_COLOR_DARK, 0x2A2A2A, 0x1E1E1E,
                               DEFAULT_PART_COLOR_DARK, DEFAULT_PART_COLOR_DARK, DEFAULT_MOVED_PART_COLOR_DARK, DEFAULT_PART_TRANSPARENCY, DEFAULT_CARET_LINE_TRANSPARENCY};
    // What the plugin's Compare Options dialog and Settings keep.
    bool DetectMoves = true, DetectSubBlockDiffs = true, DetectSubLineMoves = true, DetectCharDiffs = true;
    bool IgnoreEmptyLines = false, IgnoreFoldedLines = false, IgnoreHiddenLines = false;
    bool IgnoreChangedSpaces = false, IgnoreAllSpaces = false, IgnoreEOL = false, IgnoreCase = false;
    bool NeverMarkIgnored = false, ShowOnlyDiffs = false, ShowOnlySelDiffs = false;
    bool GotoFirstDiff = true, HideMargin = false, WrapAround = true, FollowingCaret = true;
    bool RecompareOnChange = true;
    int ChangedThresholdPercent = DEFAULT_CHANGED_THRESHOLD;
};

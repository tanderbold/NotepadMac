// The plugin's NppHelpers.h, for macOS: the markers (on numbers the port has
// free), the masks the engine works with, and the Scintilla helpers the engine
// and NotepadMac's Compare use. Ported from ComparePlus's NppHelpers; what
// reached Notepad++ through its plugin messages is left out.
#pragma once
#include <cstdint>
#include <vector>
#include <string>
#include <memory>
#include <utility>
#include "Scintilla.h"
#include "Compare.h"

// The plugin numbers these 0-15; here they dodge the port's own markers
// (1 bookmark, 6-8 git, 9 Compare's revert arrow, 21-24 change history).
enum Marker_t {
    MARKER_CHANGED_LINE = 0,
    MARKER_ADDED_LINE = 2,
    MARKER_REMOVED_LINE = 3,
    MARKER_MOVED_LINE = 4,
    MARKER_BLANK = 5,
    MARKER_CHANGED_SYMBOL = 10,
    MARKER_CHANGED_LOCAL_SYMBOL = 11,
    MARKER_ADDED_SYMBOL = 12,
    MARKER_ADDED_LOCAL_SYMBOL = 13,
    MARKER_REMOVED_SYMBOL = 14,
    MARKER_REMOVED_LOCAL_SYMBOL = 15,
    MARKER_MOVED_LINE_SYMBOL = 16,
    MARKER_MOVED_BLOCK_BEGIN_SYMBOL = 17,
    MARKER_MOVED_BLOCK_MID_SYMBOL = 18,
    MARKER_MOVED_BLOCK_END_SYMBOL = 19,
    MARKER_ARROW_SYMBOL = 20
};

constexpr int MARKER_MASK_CHANGED       = (1 << MARKER_CHANGED_LINE) | (1 << MARKER_CHANGED_SYMBOL);
constexpr int MARKER_MASK_CHANGED_LOCAL = (1 << MARKER_CHANGED_LINE) | (1 << MARKER_CHANGED_LOCAL_SYMBOL);
constexpr int MARKER_MASK_ADDED         = (1 << MARKER_ADDED_LINE) | (1 << MARKER_ADDED_SYMBOL);
constexpr int MARKER_MASK_ADDED_LOCAL   = (1 << MARKER_ADDED_LINE) | (1 << MARKER_ADDED_LOCAL_SYMBOL);
constexpr int MARKER_MASK_REMOVED       = (1 << MARKER_REMOVED_LINE) | (1 << MARKER_REMOVED_SYMBOL);
constexpr int MARKER_MASK_REMOVED_LOCAL = (1 << MARKER_REMOVED_LINE) | (1 << MARKER_REMOVED_LOCAL_SYMBOL);
constexpr int MARKER_MASK_MOVED_SINGLE  = (1 << MARKER_MOVED_LINE) | (1 << MARKER_MOVED_LINE_SYMBOL);
constexpr int MARKER_MASK_MOVED_BEGIN   = (1 << MARKER_MOVED_LINE) | (1 << MARKER_MOVED_BLOCK_BEGIN_SYMBOL);
constexpr int MARKER_MASK_MOVED_MID     = (1 << MARKER_MOVED_LINE) | (1 << MARKER_MOVED_BLOCK_MID_SYMBOL);
constexpr int MARKER_MASK_MOVED_END     = (1 << MARKER_MOVED_LINE) | (1 << MARKER_MOVED_BLOCK_END_SYMBOL);
constexpr int MARKER_MASK_MOVED         = (1 << MARKER_MOVED_LINE) | (1 << MARKER_MOVED_LINE_SYMBOL) |
                                          (1 << MARKER_MOVED_BLOCK_BEGIN_SYMBOL) | (1 << MARKER_MOVED_BLOCK_MID_SYMBOL) |
                                          (1 << MARKER_MOVED_BLOCK_END_SYMBOL);
constexpr int MARKER_MASK_BLANK         = (1 << MARKER_BLANK);
constexpr int MARKER_MASK_ARROW         = (1 << MARKER_ARROW_SYMBOL);
constexpr int MARKER_MASK_NEW_LINE      = (1 << MARKER_ADDED_LINE) | (1 << MARKER_REMOVED_LINE);
constexpr int MARKER_MASK_CHANGED_LINE  = (1 << MARKER_CHANGED_LINE);
constexpr int MARKER_MASK_MOVED_LINE    = (1 << MARKER_MOVED_LINE);
constexpr int MARKER_MASK_DIFF_LINE     = MARKER_MASK_NEW_LINE | MARKER_MASK_CHANGED_LINE;
constexpr int MARKER_MASK_LINE          = MARKER_MASK_DIFF_LINE | MARKER_MASK_MOVED_LINE;
constexpr int MARKER_MASK_SYMBOL        = (1 << MARKER_CHANGED_SYMBOL) | (1 << MARKER_CHANGED_LOCAL_SYMBOL) |
                                          (1 << MARKER_ADDED_SYMBOL) | (1 << MARKER_ADDED_LOCAL_SYMBOL) |
                                          (1 << MARKER_REMOVED_SYMBOL) | (1 << MARKER_REMOVED_LOCAL_SYMBOL) |
                                          (1 << MARKER_MOVED_LINE_SYMBOL) | (1 << MARKER_MOVED_BLOCK_BEGIN_SYMBOL) |
                                          (1 << MARKER_MOVED_BLOCK_MID_SYMBOL) | (1 << MARKER_MOVED_BLOCK_END_SYMBOL);
constexpr int MARKER_MASK_ALL           = MARKER_MASK_LINE | MARKER_MASK_SYMBOL;

extern int nppBookmarkMarker;   // a mask: 1 << the bookmark marker
extern int indicatorHighlight;  // the indicator of sub-line differences
extern int marginNum;           // the margin the symbols go in
extern int gMarginWidth;

// RAII helpers as the plugin has them.
struct ScopedViewWriteEnabler {
    ScopedViewWriteEnabler(int view) : _view(view) {
        _isRO = CallScintilla(_view, SCI_GETREADONLY, 0, 0) != 0;
        if (_isRO) CallScintilla(_view, SCI_SETREADONLY, 0, 0);
    }
    ~ScopedViewWriteEnabler() { if (_isRO) CallScintilla(_view, SCI_SETREADONLY, 1, 0); }
private:
    int _view; bool _isRO;
};
struct ScopedViewUndoAction {
    ScopedViewUndoAction(int view) : _view(view) { CallScintilla(_view, SCI_BEGINUNDOACTION, 0, 0); }
    ~ScopedViewUndoAction() { CallScintilla(_view, SCI_ENDUNDOACTION, 0, 0); }
private:
    int _view;
};

inline int getOtherViewId(int view) { return view == MAIN_VIEW ? SUB_VIEW : MAIN_VIEW; }
inline int getCodepage(int view) { return (int)CallScintilla(view, SCI_GETCODEPAGE, 0, 0); }
inline intptr_t getDocId(int view) { return CallScintilla(view, SCI_GETDOCPOINTER, 0, 0); }
inline intptr_t getLineStart(int view, intptr_t line) { return CallScintilla(view, SCI_POSITIONFROMLINE, line, 0); }
inline intptr_t getLineEnd(int view, intptr_t line) { return CallScintilla(view, SCI_GETLINEENDPOSITION, line, 0); }
inline intptr_t getLineFromPos(int view, intptr_t pos) { return CallScintilla(view, SCI_LINEFROMPOSITION, pos, 0); }
inline intptr_t getLinesCount(int view) { return CallScintilla(view, SCI_GETLINECOUNT, 0, 0); }
inline intptr_t getEndLine(int view) { return getLinesCount(view) - 1; }
inline intptr_t getEndNotEmptyLine(int view) {
    intptr_t line = getLinesCount(view) - 1;
    return (line && (getLineEnd(view, line) - getLineStart(view, line)) == 0) ? line - 1 : line;
}
inline intptr_t getVisibleFromDocLine(int view, intptr_t line) { return CallScintilla(view, SCI_VISIBLEFROMDOCLINE, line, 0); }
inline intptr_t getDocLineFromVisible(int view, intptr_t line) { return CallScintilla(view, SCI_DOCLINEFROMVISIBLE, line, 0); }
inline intptr_t getCurrentLine(int view) { return getLineFromPos(view, CallScintilla(view, SCI_GETCURRENTPOS, 0, 0)); }
inline intptr_t getFirstVisibleLine(int view) { return CallScintilla(view, SCI_GETFIRSTVISIBLELINE, 0, 0); }
inline intptr_t getFirstLine(int view) { return getDocLineFromVisible(view, getFirstVisibleLine(view)); }
inline intptr_t getLastVisibleLine(int view) { return getFirstVisibleLine(view) + CallScintilla(view, SCI_LINESONSCREEN, 0, 0) - 1; }
inline intptr_t getLastLine(int view) { return getDocLineFromVisible(view, getLastVisibleLine(view)); }
inline intptr_t getCenterVisibleLine(int view) { return getFirstVisibleLine(view) + CallScintilla(view, SCI_LINESONSCREEN, 0, 0) / 2; }
inline intptr_t getUnhiddenLine(int view, intptr_t line) { return getDocLineFromVisible(view, getVisibleFromDocLine(view, line)); }
inline intptr_t getPreviousUnhiddenLine(int view, intptr_t line) {
    intptr_t visibleLine = getVisibleFromDocLine(view, line) - 1;
    if (visibleLine < 0) visibleLine = 0;
    return getDocLineFromVisible(view, visibleLine);
}
inline bool getNextLineAfterFold(int view, intptr_t *line) {
    const intptr_t foldParent = CallScintilla(view, SCI_GETFOLDPARENT, *line, 0);
    if (foldParent < 0 || CallScintilla(view, SCI_GETFOLDEXPANDED, foldParent, 0) != 0) return false;
    *line = CallScintilla(view, SCI_GETLASTCHILD, foldParent, -1) + 1;
    return true;
}
inline intptr_t getIndicatorStartPos(int view, intptr_t pos) { return CallScintilla(view, SCI_INDICATORSTART, indicatorHighlight, pos); }
inline intptr_t getIndicatorEndPos(int view, intptr_t pos) { return CallScintilla(view, SCI_INDICATOREND, indicatorHighlight, pos); }
inline intptr_t getWrapCount(int view, intptr_t line) { return CallScintilla(view, SCI_WRAPCOUNT, line, 0); }
inline intptr_t getLineAnnotation(int view, intptr_t line) { return CallScintilla(view, SCI_ANNOTATIONGETLINES, line, 0); }
inline bool isLineAnnotated(int view, intptr_t line) { return getLineAnnotation(view, line) > 0; }
inline bool isLineMarked(int view, intptr_t line, int markMask) { return (CallScintilla(view, SCI_MARKERGET, line, 0) & markMask) != 0; }
inline bool isLineEmpty(int view, intptr_t line) { return getLineEnd(view, line) - getLineStart(view, line) == 0; }
inline bool isLineHidden(int view, intptr_t line) { return CallScintilla(view, SCI_GETLINEVISIBLE, line, 0) == 0; }
inline bool isLineFolded(int view, intptr_t line) {
    const intptr_t foldParent = CallScintilla(view, SCI_GETFOLDPARENT, line, 0);
    return foldParent >= 0 && CallScintilla(view, SCI_GETFOLDEXPANDED, foldParent, 0) == 0;
}
inline bool isLineVisible(int view, intptr_t line) {
    intptr_t lineStart = getVisibleFromDocLine(view, line);
    intptr_t lineEnd = lineStart + getWrapCount(view, line) - 1;
    return getFirstVisibleLine(view) <= lineEnd && getLastVisibleLine(view) >= lineStart;
}
inline bool isSelection(int view) { return CallScintilla(view, SCI_GETSELECTIONEND, 0, 0) - CallScintilla(view, SCI_GETSELECTIONSTART, 0, 0) != 0; }
inline bool isSelectionVertical(int view) { return CallScintilla(view, SCI_SELECTIONISRECTANGLE, 0, 0) != 0; }
inline bool isMultiSelection(int view) { return CallScintilla(view, SCI_GETSELECTIONS, 0, 0) > 1; }
inline std::pair<intptr_t, intptr_t> getSelection(int view) {
    return std::make_pair(CallScintilla(view, SCI_GETSELECTIONSTART, 0, 0), CallScintilla(view, SCI_GETSELECTIONEND, 0, 0));
}
inline void clearSelection(int view) { CallScintilla(view, SCI_SETEMPTYSELECTION, CallScintilla(view, SCI_GETCURRENTPOS, 0, 0), 0); }
inline void setSelection(int view, intptr_t start, intptr_t end, bool scrollView = false) {
    if (scrollView) CallScintilla(view, SCI_SETSEL, start, end);
    else { CallScintilla(view, SCI_SETSELECTIONSTART, start, 0); CallScintilla(view, SCI_SETSELECTIONEND, end, 0); }
}
inline void clearAnnotation(int view, intptr_t line) { CallScintilla(view, SCI_ANNOTATIONSETTEXT, line, (sptr_t)nullptr); }
inline void clearMarks(int view, intptr_t line) { CallScintilla(view, SCI_MARKERDELETE, line, -1); }

std::pair<intptr_t, intptr_t> getSelectionLines(int view);
std::vector<char> getText(int view, intptr_t startPos, intptr_t endPos);
std::vector<char> getLineText(int view, intptr_t line, bool includeEOL);
void markTextAsChanged(int view, intptr_t start, intptr_t length, int color);
void clearChangedIndicator(int view, intptr_t start, intptr_t length);
void clearChangedIndicatorFull(int view);
void setStyles(UserSettings &settings);
void setNormalView(int view);
void setCompareView(int view, bool showMargin, int blankColor, int caretLineTransp);
void clearWindow(int view, bool clearIndicators = true);
void clearMarks(int view, intptr_t startLine, intptr_t length);
void clearAnnotations(int view, intptr_t startLine, intptr_t length);
bool isAdjacentAnnotation(int view, intptr_t line, bool down);
bool isAdjacentAnnotationVisible(int view, intptr_t line, bool down);
void addBlankSection(int view, intptr_t line, intptr_t length, intptr_t textLinePos = 0, const char *text = nullptr);
void addBlankSectionAfter(int view, intptr_t line, intptr_t length);
std::vector<intptr_t> getFoldedLines(int view);
void setFoldedLines(int view, const std::vector<intptr_t> &foldedLines);
void unhideAllLines(int view);
intptr_t otherViewMatchingLine(int view, intptr_t line, intptr_t adjustment = 0, bool check = false);
void centerAt(int view, intptr_t line);
int showArrowSymbol(int view, intptr_t line, bool down);

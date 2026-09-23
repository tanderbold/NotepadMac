// See NppHelpers.h. Ported from ComparePlus's NppHelpers.cpp.
#include <cstring>
#include <string>
#include <vector>
#include <cwctype>
#include <cstdio>
#include "NppHelpers.h"
#include "Tools.h"
#include "ProgressDlg.h"
#include "../Icons/icon_added.h"
#include "../Icons/icon_changed.h"
#include "../Icons/icon_moved.h"
#include "../Icons/icon_removed.h"
#include "../Icons/icon_arrows.h"

NppData nppData;
SciFnDirect sciFunc = nullptr;
sptr_t sciPtr[2] = {0, 0};
UserSettings Settings;
int nppBookmarkMarker = 1 << 1;
int indicatorHighlight = 18;
int marginNum = 5;
int gMarginWidth = 16;
const std::string ProgressDlg::cCancelledCause = "Compare cancelled";

static progress_ptr gProgress;
progress_ptr &ProgressDlg::Open(const wchar_t *) { gProgress = std::make_shared<ProgressDlg>(); return gProgress; }
progress_ptr &ProgressDlg::Get() { if (!gProgress) gProgress = std::make_shared<ProgressDlg>(); return gProgress; }
void ProgressDlg::Close() { gProgress.reset(); }

#pragma mark - Win32 stand-ins

int MultiByteToWideChar(UINT, DWORD, const char *mb, int mbLen, wchar_t *wc, int wcLen) {
    if (mbLen < 0) mbLen = (int)strlen(mb);
    int out = 0;
    for (int i = 0; i < mbLen;) {
        unsigned char c = (unsigned char)mb[i];
        uint32_t cp; int n;
        if (c < 0x80) { cp = c; n = 1; }
        else if ((c & 0xE0) == 0xC0 && i + 1 < mbLen) { cp = ((c & 0x1F) << 6) | (mb[i + 1] & 0x3F); n = 2; }
        else if ((c & 0xF0) == 0xE0 && i + 2 < mbLen) { cp = ((c & 0x0F) << 12) | ((mb[i + 1] & 0x3F) << 6) | (mb[i + 2] & 0x3F); n = 3; }
        else if ((c & 0xF8) == 0xF0 && i + 3 < mbLen) { cp = ((c & 0x07) << 18) | ((mb[i + 1] & 0x3F) << 12) | ((mb[i + 2] & 0x3F) << 6) | (mb[i + 3] & 0x3F); n = 4; }
        else { cp = 0xFFFD; n = 1; }
        if (wc) { if (out >= wcLen) break; wc[out] = (wchar_t)cp; }
        out++;
        i += n;
    }
    return out;
}

int WideCharToMultiByte(UINT, DWORD, const wchar_t *wc, int wcLen, char *mb, int mbLen, const char *, BOOL *) {
    if (wcLen < 0) wcLen = (int)wcslen(wc);
    int out = 0;
    for (int i = 0; i < wcLen; ++i) {
        uint32_t cp = (uint32_t)wc[i];
        char buf[4]; int n;
        if (cp < 0x80) { buf[0] = (char)cp; n = 1; }
        else if (cp < 0x800) { buf[0] = (char)(0xC0 | (cp >> 6)); buf[1] = (char)(0x80 | (cp & 0x3F)); n = 2; }
        else if (cp < 0x10000) { buf[0] = (char)(0xE0 | (cp >> 12)); buf[1] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[2] = (char)(0x80 | (cp & 0x3F)); n = 3; }
        else { buf[0] = (char)(0xF0 | (cp >> 18)); buf[1] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[2] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[3] = (char)(0x80 | (cp & 0x3F)); n = 4; }
        if (mb) { if (out + n > mbLen) break; memcpy(mb + out, buf, (size_t)n); }
        out += n;
    }
    return out;
}

wchar_t *CharLowerW(wchar_t *s) { for (wchar_t *p = s; *p; ++p) *p = (wchar_t)towlower((wint_t)*p); return s; }
BOOL IsCharAlphaNumericW(wchar_t c) { return iswalnum((wint_t)c) ? TRUE : FALSE; }
int MessageBoxA(HWND, const char *text, const char *caption, UINT) { fprintf(stderr, "%s: %s\n", caption, text); return 0; }

void toLowerCase(std::vector<char> &text, int codepage) {
    const int len = (int)text.size();
    if (!len) return;
    const int wLen = MultiByteToWideChar(codepage, 0, text.data(), len, nullptr, 0);
    std::vector<wchar_t> wText((size_t)wLen + 1, 0);
    MultiByteToWideChar(codepage, 0, text.data(), len, wText.data(), wLen);
    for (int i = 0; i < wLen; ++i) wText[(size_t)i] = (wchar_t)towlower((wint_t)wText[(size_t)i]);
    const int mbLen = WideCharToMultiByte(codepage, 0, wText.data(), wLen, nullptr, 0);
    text.resize((size_t)mbLen);
    WideCharToMultiByte(codepage, 0, wText.data(), wLen, text.data(), mbLen);
}
std::wstring MBtoWC(const char *mb, int len, int codepage) {
    const int wLen = MultiByteToWideChar(codepage, 0, mb, len, nullptr, 0);
    std::wstring out((size_t)wLen, 0);
    MultiByteToWideChar(codepage, 0, mb, len, out.data(), wLen);
    return out;
}
std::string WCtoMB(const wchar_t *wc, int len, int codepage) {
    const int mbLen = WideCharToMultiByte(codepage, 0, wc, len, nullptr, 0);
    std::string out((size_t)mbLen, 0);
    WideCharToMultiByte(codepage, 0, wc, len, out.data(), mbLen);
    return out;
}

#pragma mark - Styles and views

namespace {
bool compareMode[2] = {false, false};
int blankStyle[2] = {0, 0};
bool endAtLastLine[2] = {true, true};
int caretLineColor[2] = {0, 0};
int caretLineLayer[2] = {0, 0};

void defineColor(int type, int color) {
    for (int view = 0; view < 2; ++view) {
        CallScintilla(view, SCI_MARKERDEFINE, type, SC_MARK_BACKGROUND);
        CallScintilla(view, SCI_MARKERSETBACK, type, color);
    }
}
void defineRgbaSymbol(int type, const unsigned char *rgba) {
    for (int view = 0; view < 2; ++view) CallScintilla(view, SCI_MARKERDEFINERGBAIMAGE, type, (sptr_t)rgba);
}
void setTextStyle(int transparency) {
    const int alpha = ((100 - transparency) * 100 / 100);
    for (int view = 0; view < 2; ++view) {
        CallScintilla(view, SCI_INDICSETSTYLE, indicatorHighlight, INDIC_ROUNDBOX);
        CallScintilla(view, SCI_INDICSETFLAGS, indicatorHighlight, SC_INDICFLAG_VALUEFORE);
        CallScintilla(view, SCI_INDICSETALPHA, indicatorHighlight, alpha);
    }
}
void setBlanksStyle(int view, int blankColor) {
    if (blankStyle[view] == 0) blankStyle[view] = (int)CallScintilla(view, SCI_ALLOCATEEXTENDEDSTYLES, 1, 0);
    CallScintilla(view, SCI_ANNOTATIONSETSTYLEOFFSET, blankStyle[view], 0);
    CallScintilla(view, SCI_STYLESETEOLFILLED, blankStyle[view], 1);
    CallScintilla(view, SCI_STYLESETBACK, blankStyle[view], blankColor);
    CallScintilla(view, SCI_STYLESETBOLD, blankStyle[view], 1);
    CallScintilla(view, SCI_ANNOTATIONSETVISIBLE, ANNOTATION_STANDARD, 0);
}
}

void setStyles(UserSettings &settings) {
    const int bg = (int)CallScintilla(MAIN_VIEW, SCI_STYLEGETBACK, STYLE_DEFAULT, 0);
    settings.colors()._default = bg;
    int r = bg & 0xFF, g = (bg >> 8) & 0xFF, b = (bg >> 16) & 0xFF;
    constexpr int colorShift = 20;
    r = (r > colorShift) ? (r - colorShift) & 0xFF : 0;
    g = (g > colorShift) ? (g - colorShift) & 0xFF : 0;
    b = (b > colorShift) ? (b - colorShift) & 0xFF : 0;
    settings.colors().blank = r | (g << 8) | (b << 16);
    defineColor(MARKER_ADDED_LINE, settings.colors().added);
    defineColor(MARKER_REMOVED_LINE, settings.colors().removed);
    defineColor(MARKER_MOVED_LINE, settings.colors().moved);
    defineColor(MARKER_CHANGED_LINE, settings.colors().changed);
    defineColor(MARKER_BLANK, settings.colors().blank);
    for (int view = 0; view < 2; ++view) {
        CallScintilla(view, SCI_RGBAIMAGESETWIDTH, 14, 0);
        CallScintilla(view, SCI_RGBAIMAGESETHEIGHT, 14, 0);
        CallScintilla(view, SCI_RGBAIMAGESETSCALE, 100, 0);
    }
    defineRgbaSymbol(MARKER_CHANGED_SYMBOL, icon_changed);
    defineRgbaSymbol(MARKER_CHANGED_LOCAL_SYMBOL, icon_changed_local);
    defineRgbaSymbol(MARKER_ADDED_SYMBOL, icon_added);
    defineRgbaSymbol(MARKER_ADDED_LOCAL_SYMBOL, icon_added_local);
    defineRgbaSymbol(MARKER_REMOVED_SYMBOL, icon_removed);
    defineRgbaSymbol(MARKER_REMOVED_LOCAL_SYMBOL, icon_removed_local);
    defineRgbaSymbol(MARKER_MOVED_LINE_SYMBOL, icon_moved_line);
    defineRgbaSymbol(MARKER_MOVED_BLOCK_BEGIN_SYMBOL, icon_moved_block_start);
    defineRgbaSymbol(MARKER_MOVED_BLOCK_MID_SYMBOL, icon_moved_block_middle);
    defineRgbaSymbol(MARKER_MOVED_BLOCK_END_SYMBOL, icon_moved_block_end);
    setTextStyle(settings.colors().part_transparency);
}

void setNormalView(int view) {
    if (!compareMode[view]) return;
    compareMode[view] = false;
    CallScintilla(view, SCI_SETENDATLASTLINE, endAtLastLine[view], 0);
    if (marginNum >= 0) {
        CallScintilla(view, SCI_SETMARGINMASKN, marginNum, 0);
        CallScintilla(view, SCI_SETMARGINWIDTHN, marginNum, 0);
        CallScintilla(view, SCI_SETMARGINSENSITIVEN, marginNum, 0);
    }
    if (CallScintilla(view, SCI_GETCARETLINEVISIBLE, 0, 0)) {
        CallScintilla(view, SCI_SETCARETLINEVISIBLE, 0, 0);
        CallScintilla(view, SCI_SETELEMENTCOLOUR, SC_ELEMENT_CARET_LINE_BACK, caretLineColor[view]);
        CallScintilla(view, SCI_SETCARETLINELAYER, caretLineLayer[view], 0);
        CallScintilla(view, SCI_SETCARETLINEVISIBLE, 1, 0);
    }
    CallScintilla(view, SCI_ANNOTATIONSETSTYLEOFFSET, 0, 0);
}

void setCompareView(int view, bool showMargin, int blankColor, int caretLineTransp) {
    if (!compareMode[view]) {
        compareMode[view] = true;
        endAtLastLine[view] = CallScintilla(view, SCI_GETENDATLASTLINE, 0, 0) != 0;
        CallScintilla(view, SCI_SETENDATLASTLINE, 0, 0);
        if (showMargin && marginNum >= 0) {
            // The revert arrow (marker 9) lives in this margin too - NotepadMac's own.
            CallScintilla(view, SCI_SETMARGINMASKN, marginNum, (sptr_t)(MARKER_MASK_SYMBOL | MARKER_MASK_ARROW | (1 << 9)));
            CallScintilla(view, SCI_SETMARGINWIDTHN, marginNum, gMarginWidth);
            CallScintilla(view, SCI_SETMARGINSENSITIVEN, marginNum, 1);
        }
        caretLineColor[view] = (int)CallScintilla(view, SCI_GETELEMENTCOLOUR, SC_ELEMENT_CARET_LINE_BACK, 0);
        caretLineLayer[view] = (int)CallScintilla(view, SCI_GETCARETLINELAYER, 0, 0);
    }
    if (CallScintilla(view, SCI_GETCARETLINEVISIBLE, 0, 0)) {
        const intptr_t alpha = ((100 - caretLineTransp) * SC_ALPHA_OPAQUE / 100);
        CallScintilla(view, SCI_SETCARETLINEVISIBLE, 0, 0);
        CallScintilla(view, SCI_SETELEMENTCOLOUR, SC_ELEMENT_CARET_LINE_BACK, (caretLineColor[view] & 0xFFFFFF) | (alpha << 24));
        CallScintilla(view, SCI_SETCARETLINELAYER, SC_LAYER_UNDER_TEXT, 0);
        CallScintilla(view, SCI_SETCARETLINEVISIBLE, 1, 0);
    }
    setBlanksStyle(view, blankColor);
}

#pragma mark - Text, marks, annotations

std::pair<intptr_t, intptr_t> getSelectionLines(int view) {
    if (isSelectionVertical(view) || isMultiSelection(view)) return std::make_pair(-1, -1);
    const intptr_t selectionStart = CallScintilla(view, SCI_GETSELECTIONSTART, 0, 0);
    const intptr_t selectionEnd = CallScintilla(view, SCI_GETSELECTIONEND, 0, 0);
    if (selectionEnd - selectionStart == 0) return std::make_pair(-1, -1);
    intptr_t startLine = getLineFromPos(view, selectionStart), endLine = getLineFromPos(view, selectionEnd);
    if (selectionEnd == getLineStart(view, endLine)) --endLine;
    return std::make_pair(startLine, endLine);
}

std::vector<char> getText(int view, intptr_t startPos, intptr_t endPos) {
    const intptr_t len = endPos - startPos;
    if (len <= 0) return {};
    std::vector<char> text((size_t)len + 1, 0);
    Sci_TextRangeFull tr;
    tr.chrg.cpMin = startPos;
    tr.chrg.cpMax = endPos;
    tr.lpstrText = text.data();
    CallScintilla(view, SCI_GETTEXTRANGEFULL, 0, (sptr_t)&tr);
    return text;
}

std::vector<char> getLineText(int view, intptr_t line, bool includeEOL) {
    const intptr_t start = getLineStart(view, line);
    const intptr_t end = includeEOL ? start + CallScintilla(view, SCI_LINELENGTH, line, 0) : getLineEnd(view, line);
    std::vector<char> text = getText(view, start, end);
    if (!text.empty()) text.pop_back();   // the terminator getText adds
    return text;
}

void markTextAsChanged(int view, intptr_t start, intptr_t length, int color) {
    if (length <= 0) return;
    const int curIndic = (int)CallScintilla(view, SCI_GETINDICATORCURRENT, 0, 0);
    CallScintilla(view, SCI_SETINDICATORCURRENT, indicatorHighlight, 0);
    CallScintilla(view, SCI_SETINDICATORVALUE, color | SC_INDICVALUEBIT, 0);
    CallScintilla(view, SCI_INDICATORFILLRANGE, start, length);
    CallScintilla(view, SCI_SETINDICATORCURRENT, curIndic, 0);
}

void clearChangedIndicator(int view, intptr_t start, intptr_t length) {
    if (length <= 0) return;
    const int curIndic = (int)CallScintilla(view, SCI_GETINDICATORCURRENT, 0, 0);
    CallScintilla(view, SCI_SETINDICATORCURRENT, indicatorHighlight, 0);
    CallScintilla(view, SCI_INDICATORCLEARRANGE, start, length);
    CallScintilla(view, SCI_SETINDICATORCURRENT, curIndic, 0);
}

void clearChangedIndicatorFull(int view) { clearChangedIndicator(view, 0, CallScintilla(view, SCI_GETLENGTH, 0, 0)); }

void clearWindow(int view, bool clearIndicators) {
    CallScintilla(view, SCI_ANNOTATIONCLEARALL, 0, 0);
    for (int m : {MARKER_CHANGED_LINE, MARKER_ADDED_LINE, MARKER_REMOVED_LINE, MARKER_MOVED_LINE, MARKER_BLANK,
                  MARKER_CHANGED_SYMBOL, MARKER_CHANGED_LOCAL_SYMBOL, MARKER_ADDED_SYMBOL, MARKER_ADDED_LOCAL_SYMBOL,
                  MARKER_REMOVED_SYMBOL, MARKER_REMOVED_LOCAL_SYMBOL, MARKER_MOVED_LINE_SYMBOL, MARKER_MOVED_BLOCK_BEGIN_SYMBOL,
                  MARKER_MOVED_BLOCK_MID_SYMBOL, MARKER_MOVED_BLOCK_END_SYMBOL, MARKER_ARROW_SYMBOL})
        CallScintilla(view, SCI_MARKERDELETEALL, m, 0);
    if (clearIndicators) clearChangedIndicatorFull(view);
    CallScintilla(view, SCI_COLOURISE, 0, -1);
}

void clearMarks(int view, intptr_t startLine, intptr_t length) {
    intptr_t linesCount = getLinesCount(view);
    if (startLine + length < linesCount) linesCount = startLine + length;
    const intptr_t startPos = getLineStart(view, startLine);
    clearChangedIndicator(view, startPos, getLineEnd(view, linesCount - 1) - startPos);
    for (; startLine < linesCount; ++startLine) clearMarks(view, startLine);
}

void clearAnnotations(int view, intptr_t startLine, intptr_t length) {
    intptr_t endLine = getLinesCount(view);
    if (startLine + length < endLine) endLine = startLine + length;
    for (; startLine < endLine; ++startLine) clearAnnotation(view, startLine);
}

bool isAdjacentAnnotation(int view, intptr_t line, bool down) {
    if (down) return isLineAnnotated(view, line);
    return line && isLineAnnotated(view, getPreviousUnhiddenLine(view, line));
}

bool isAdjacentAnnotationVisible(int view, intptr_t line, bool down) {
    if (down) {
        if (!isLineAnnotated(view, line)) return false;
        if (getVisibleFromDocLine(view, line) + getWrapCount(view, line) > getLastVisibleLine(view)) return false;
    } else {
        if (!line || !isLineAnnotated(view, getPreviousUnhiddenLine(view, line))) return false;
        if (getVisibleFromDocLine(view, line) - 1 < getFirstVisibleLine(view)) return false;
    }
    return true;
}

void addBlankSection(int view, intptr_t line, intptr_t length, intptr_t textLinePos, const char *text) {
    if (length <= 0) return;
    std::vector<char> blank((size_t)length - 1, '\n');
    if (textLinePos > 0 && text != nullptr) {
        if (length < textLinePos) return;
        blank.insert(blank.begin() + textLinePos - 1, text, text + strlen(text));
    }
    blank.push_back('\0');
    CallScintilla(view, SCI_ANNOTATIONSETTEXT, getPreviousUnhiddenLine(view, line), (sptr_t)blank.data());
}

void addBlankSectionAfter(int view, intptr_t line, intptr_t length) {
    if (length <= 0) return;
    std::vector<char> blank((size_t)length - 1, '\n');
    blank.push_back('\0');
    CallScintilla(view, SCI_ANNOTATIONSETTEXT, getUnhiddenLine(view, line), (sptr_t)blank.data());
}

std::vector<intptr_t> getFoldedLines(int view) {
    if (CallScintilla(view, SCI_GETALLLINESVISIBLE, 0, 0)) return {};
    const intptr_t linesCount = getLinesCount(view);
    std::vector<intptr_t> foldedLines;
    for (intptr_t line = 0; line < linesCount; ++line) {
        line = CallScintilla(view, SCI_CONTRACTEDFOLDNEXT, line, 0);
        if (line < 0) break;
        foldedLines.emplace_back(line);
    }
    return foldedLines;
}

void setFoldedLines(int view, const std::vector<intptr_t> &foldedLines) {
    for (auto line : foldedLines) CallScintilla(view, SCI_FOLDLINE, line, SC_FOLDACTION_CONTRACT);
}

void unhideAllLines(int view) {
    const intptr_t linesCount = getLinesCount(view);
    auto foldedLines = getFoldedLines(view);
    CallScintilla(view, SCI_SHOWLINES, 0, linesCount - 1);
    setFoldedLines(view, foldedLines);
}

intptr_t otherViewMatchingLine(int view, intptr_t line, intptr_t adjustment, bool check) {
    const int otherView = getOtherViewId(view);
    const intptr_t otherLineCount = getLinesCount(otherView);
    const intptr_t otherLine = getDocLineFromVisible(otherView, getVisibleFromDocLine(view, line) + adjustment);
    if (check && (otherLine < otherLineCount) && (otherViewMatchingLine(otherView, otherLine, -adjustment) != line)) return -1;
    return (otherLine >= otherLineCount) ? otherLineCount - 1 : otherLine;
}

void centerAt(int view, intptr_t line) {
    const intptr_t firstVisible = getVisibleFromDocLine(view, line) - CallScintilla(view, SCI_LINESONSCREEN, 0, 0) / 2;
    CallScintilla(view, SCI_SETFIRSTVISIBLELINE, firstVisible, 0);
}

int showArrowSymbol(int view, intptr_t line, bool down) {
    CallScintilla(view, SCI_MARKERDEFINERGBAIMAGE, MARKER_ARROW_SYMBOL, (sptr_t)(down ? icon_arrow_down : icon_arrow_up));
    return (int)CallScintilla(view, SCI_MARKERADD, line, MARKER_ARROW_SYMBOL);
}

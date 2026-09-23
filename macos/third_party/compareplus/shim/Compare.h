// The plugin's Compare.h, reduced to what the engine reaches for: the two
// views by number, CallScintilla, the settings, and the log macros (silent).
#pragma once
#include <string>
#include "windows.h"
#include "UserSettings.h"

#define MAIN_VIEW 0
#define SUB_VIEW 1

typedef uintptr_t uptr_t;
typedef intptr_t sptr_t;
typedef sptr_t (*SciFnDirect)(sptr_t ptr, unsigned int iMessage, uptr_t wParam, sptr_t lParam);

struct NppData { HWND _nppHandle {nullptr}; };
extern NppData nppData;
extern SciFnDirect sciFunc;
extern sptr_t sciPtr[2];
extern UserSettings Settings;

inline LRESULT CallScintilla(int viewNum, unsigned int uMsg, uptr_t wParam, sptr_t lParam) {
    return sciFunc(sciPtr[viewNum], uMsg, wParam, lParam);
}

#define LOGD_GET_TIME
#define LOGD(LOG_FILTER, STR)
#define LOGDIF(LOG_FILTER, COND, STR)
#define LOGDB(LOG_FILTER, BUFFID, STR)
#define PRINT_DIFFS(INFO, DIFFS)

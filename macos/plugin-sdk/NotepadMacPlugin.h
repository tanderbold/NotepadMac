/* NotepadMac plugin interface.
 *
 * The macOS counterpart of Notepad++'s PluginInterface.h: a plugin is a
 * dynamic library (.dylib) in the plugins folder - Run > Open Plugins Folder
 * shows it - either flat or, as on Windows, in a folder of its own name:
 *
 *     …/Application Support/NotepadMac/plugins/MyPlugin/MyPlugin.dylib
 *
 * Where Windows passes window handles and messages, this passes opaque
 * handles and one function pointer, `send`. Strings are UTF-8 char*, never
 * wchar_t. Message and notification numbers are Notepad++'s own, so the
 * Windows documentation applies where a message is listed here.
 *
 * A plugin exports, with C linkage:
 *
 *   void              nppmac_setInfo(NppMacData data);            // required
 *   const char       *nppmac_getName(void);                       // required
 *   NppMacFuncItem   *nppmac_getFuncsArray(int *count);           // required
 *   void              nppmac_beNotified(const NppMacNotification *); // optional
 *   intptr_t          nppmac_messageProc(uint32_t message,
 *                                        uintptr_t wParam, intptr_t lParam); // optional
 *
 * getFuncsArray returns a static array that must stay alive for the life of
 * the plugin; each entry becomes an item of the plugin's submenu in the
 * Plugins menu, in order; an entry whose pFunc is null is a separator.
 *
 * Everything runs on the main thread. Compile with e.g.
 *   clang -dynamiclib -o MyPlugin.dylib myplugin.c
 */
#ifndef NOTEPADMAC_PLUGIN_H
#define NOTEPADMAC_PLUGIN_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *NppMacHandle;

/* The one call a plugin makes back into the application.
 * target = data.scintillaHandle: a Scintilla SCI_* message to the active
 *          editor view (see Scintilla's documentation; this is the whole
 *          editing API and works exactly as on Windows).
 * target = data.nppHandle: an NPPM_* message from the list below. */
typedef intptr_t (*NppMacSendFn)(NppMacHandle target, uint32_t message,
                                 uintptr_t wParam, intptr_t lParam);

typedef struct {
    NppMacHandle nppHandle;
    NppMacHandle scintillaHandle;
    NppMacSendFn send;
} NppMacData;

typedef void (*NppMacPluginFunc)(void);

enum { NppMacMenuItemSize = 128 };

typedef struct {
    char itemName[NppMacMenuItemSize];  /* UTF-8 menu item title */
    NppMacPluginFunc pFunc;             /* null: a separator */
} NppMacFuncItem;

typedef struct {
    uint32_t code;          /* an NPPN_* number below */
    uintptr_t idFrom;       /* 0 for now */
    NppMacHandle hwndFrom;  /* the application's nppHandle */
} NppMacNotification;

/* --- NPPM_* messages this host answers (numbers are Notepad++'s). ---
 * The string-returning ones write UTF-8 into (char *)lParam of wParam bytes
 * and return the length written; with lParam null they return the size a
 * buffer needs, terminator included. */
#define NPPMAC_WM_USER 1024
#define NPPMSG (NPPMAC_WM_USER + 1000)
#define NPPM_GETCURRENTSCINTILLA (NPPMSG + 4)   /* *(intptr_t*)lParam = 0: one view is active */
#define NPPM_SAVECURRENTFILE     (NPPMSG + 38)  /* returns 1 when saved */
#define NPPM_GETPLUGINSCONFIGDIR (NPPMSG + 46)  /* a folder the plugin may write settings in */
#define NPPM_GETNPPVERSION       (NPPMSG + 50)  /* Notepad++ base version: high word 8, low word 908 */
#define NPPM_DOOPEN              (NPPMSG + 77)  /* lParam = const char *path; returns 1 when opened */
#define NPPMAC_RUNCOMMAND_USER (NPPMAC_WM_USER + 3000)
#define NPPM_GETFULLCURRENTPATH  (NPPMAC_RUNCOMMAND_USER + 1)
#define NPPM_GETCURRENTDIRECTORY (NPPMAC_RUNCOMMAND_USER + 2)
#define NPPM_GETFILENAME         (NPPMAC_RUNCOMMAND_USER + 3)

/* --- NPPN_* notifications this host sends (numbers are Notepad++'s). --- */
#define NPPN_FIRST 1000
#define NPPN_READY           (NPPN_FIRST + 1)
#define NPPN_FILEOPENED      (NPPN_FIRST + 4)
#define NPPN_FILESAVED       (NPPN_FIRST + 8)
#define NPPN_SHUTDOWN        (NPPN_FIRST + 9)
#define NPPN_BUFFERACTIVATED (NPPN_FIRST + 10)

#ifdef __cplusplus
}
#endif

#endif /* NOTEPADMAC_PLUGIN_H */

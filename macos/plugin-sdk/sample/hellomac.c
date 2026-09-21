/* The smallest useful NotepadMac plugin: two menu commands and a
 * notification counter. Build and install:
 *
 *   clang -dynamiclib -o HelloMac.dylib hellomac.c
 *   mkdir -p "$HOME/Library/Application Support/NotepadMac/plugins/HelloMac"
 *   cp HelloMac.dylib "$HOME/Library/Application Support/NotepadMac/plugins/HelloMac/"
 *
 * and restart NotepadMac: a HelloMac submenu appears in the Plugins menu.
 */
#include "../NotepadMacPlugin.h"
#include <string.h>

#define SCI_REPLACESEL 2170   /* from Scintilla.h */

static NppMacData npp;

enum { kNotificationCodes = 2048 };
static int notified[kNotificationCodes];

static void insertGreeting(void)
{
    npp.send(npp.scintillaHandle, SCI_REPLACESEL, 0, (intptr_t)"hello from the sample plugin");
}

static void insertFileName(void)
{
    char name[1024] = "";
    npp.send(npp.nppHandle, NPPM_GETFILENAME, sizeof name, (intptr_t)name);
    npp.send(npp.scintillaHandle, SCI_REPLACESEL, 0, (intptr_t)name);
}

static NppMacFuncItem items[] = {
    { "Insert Greeting",  insertGreeting },
    { "",                 0 },              /* a separator */
    { "Insert File Name", insertFileName },
};

void nppmac_setInfo(NppMacData data) { npp = data; }

const char *nppmac_getName(void) { return "HelloMac"; }

NppMacFuncItem *nppmac_getFuncsArray(int *count)
{
    *count = (int)(sizeof(items) / sizeof(items[0]));
    return items;
}

void nppmac_beNotified(const NppMacNotification *notification)
{
    if (notification->code < kNotificationCodes) notified[notification->code]++;
}

/* Message 1 answers how many times the NPPN_* code in wParam has arrived -
 * only so the test suite can watch notifications land. */
intptr_t nppmac_messageProc(uint32_t message, uintptr_t wParam, intptr_t lParam)
{
    (void)lParam;
    if (message == 1 && wParam < kNotificationCodes) return notified[wParam];
    return 0;
}

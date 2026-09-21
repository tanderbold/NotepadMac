# Writing a NotepadMac plugin

NotepadMac loads third-party plugins the way Notepad++ does on Windows,
adapted to macOS: a plugin is a **dynamic library** (`.dylib`) with a small C
interface, [`NotepadMacPlugin.h`](NotepadMacPlugin.h). If you have written a
Notepad++ plugin, you know this interface already - the differences are that
strings are UTF-8 `char *` instead of `wchar_t *`, and that instead of posting
window messages you call the one `send` function you are handed.

## Where plugins live

```
~/Library/Application Support/NotepadMac/plugins/<Name>/<Name>.dylib
```

(a flat `plugins/<Name>.dylib` works too). *Run > Open Plugins Folder* opens
the folder; plugins are loaded at launch, and each one becomes a submenu of
the **Plugins** menu.

## The interface

A plugin exports three required entry points and two optional ones, all with
C linkage - see the sample in [`sample/hellomac.c`](sample/hellomac.c):

| Export | Windows counterpart | |
|---|---|---|
| `nppmac_setInfo(NppMacData)` | `setInfo(NppData)` | hands you the handles and `send` |
| `nppmac_getName()` | `getName()` | your submenu's title, UTF-8 |
| `nppmac_getFuncsArray(int *count)` | `getFuncsArray` | your menu items; null `pFunc` = separator |
| `nppmac_beNotified(const NppMacNotification *)` | `beNotified` | optional |
| `nppmac_messageProc(msg, wParam, lParam)` | `messageProc` | optional |

Everything runs on the main thread.

### Talking to the editor

`send(data.scintillaHandle, SCI_*, wParam, lParam)` sends any Scintilla
message to the active editor view - this is the same editing API Notepad++
plugins use on Windows, documented at scintilla.org. Text you pass or receive
is UTF-8.

`send(data.nppHandle, NPPM_*, wParam, lParam)` answers the application-level
messages listed in `NotepadMacPlugin.h` (current file path and name, open a
file, save the current file, a config folder of your own, and so on), with
Notepad++'s own message numbers. String-returning messages write UTF-8 into
`(char *)lParam` of `wParam` bytes; call them with a null `lParam` to learn
the needed size. The set grows as plugins need more - ask in the issues.

### Notifications

`nppmac_beNotified` receives `NPPN_READY`, `NPPN_FILEOPENED`,
`NPPN_FILESAVED`, `NPPN_BUFFERACTIVATED` and `NPPN_SHUTDOWN`, with Notepad++'s
numbers in `code`.

## Building

```sh
clang -dynamiclib -o MyPlugin.dylib myplugin.c
```

Any language that can export C symbols from a dylib works (C, C++,
Objective-C, Swift with `@_cdecl`, Rust with `#[no_mangle] extern "C"`).
Universal builds are polite but not required: an arm64-only plugin loads on
Apple silicon, an x86_64-only one under Rosetta or on Intel.

Release builds of NotepadMac are signed with library validation disabled, so
a plugin does not need to be signed by the same developer; macOS still asks
its usual questions about downloaded, unsigned code (`xattr -d
com.apple.quarantine MyPlugin.dylib` after inspecting a download you trust).
A plugin runs with the application's privileges: only install plugins whose
source you have seen or whose author you trust.

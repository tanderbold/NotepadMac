// What the ComparePlus engine takes from <windows.h>, on macOS.
#pragma once
#include <cstdint>
#include <cstddef>
#include <cwchar>
#include <string>
#include <vector>

typedef intptr_t  LRESULT;
typedef intptr_t  LPARAM;
typedef uintptr_t WPARAM;
#ifndef OBJC_BOOL_DEFINED
typedef int       BOOL;
#endif
typedef unsigned int UINT;
typedef unsigned long DWORD;
typedef void     *HWND;
typedef const wchar_t *LPCWSTR;
typedef wchar_t  *LPWSTR;
typedef const char *LPCSTR;
typedef char     *LPSTR;
#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif
#define CP_UTF8 65001
#define MB_OK 0
#define MB_ICONWARNING 0
#define MB_ICONERROR 0
#define MAX_PATH 1024

// UTF-8 <-> wchar_t (32-bit here). The engine only ever counts and slices
// through these, so both directions agree with each other and with the bytes
// Scintilla holds, which is all that matters.
int MultiByteToWideChar(UINT codepage, DWORD flags, const char *mb, int mbLen, wchar_t *wc, int wcLen);
int WideCharToMultiByte(UINT codepage, DWORD flags, const wchar_t *wc, int wcLen, char *mb, int mbLen,
                        const char *defaultChar = nullptr, BOOL *usedDefault = nullptr);
wchar_t *CharLowerW(wchar_t *s);
BOOL IsCharAlphaNumericW(wchar_t c);
int MessageBoxA(HWND owner, const char *text, const char *caption, UINT type);

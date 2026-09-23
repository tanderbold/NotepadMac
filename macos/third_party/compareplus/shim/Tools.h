// The two helpers of the plugin's Tools.h the engine uses.
#pragma once
#include <string>
#include <vector>
#include "windows.h"
void toLowerCase(std::vector<char> &text, int codepage = CP_UTF8);
std::wstring MBtoWC(const char *mb, int len = -1, int codepage = CP_UTF8);
std::string WCtoMB(const wchar_t *wc, int len = -1, int codepage = CP_UTF8);

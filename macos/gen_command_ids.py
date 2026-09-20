#!/usr/bin/env python3
"""Generates macos/app/CommandIDs.h from the Windows and Scintilla sources.

    python3 macos/gen_command_ids.py

Three tables, so that shortcuts.xml written here reads on Windows and the
other way round:

  - every menu command of Notepad_plus.rc with its numeric id from
    menuCmdID.h, its menu path and its label;
  - the Scintilla commands the Windows Shortcut Mapper lists (scintKeyDefs
    in Parameters.cpp) with their Windows default keys;
  - the keys Scintilla itself assigns by default on macOS (KeyMap.cxx with
    OS_X_KEYS), which is what the port shows as a Scintilla command's key.
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "PowerEditor", "src")


def defines(path):
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\s*#define\s+(\w+)\s+(.+?)\s*(//.*)?$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def evaluate(raw, known, depth=0):
    if depth > 20:
        return None
    expr = raw
    for name in sorted(set(re.findall(r"[A-Za-z_]\w*", raw)), key=len, reverse=True):
        if name in known:
            value = known[name]
            if not isinstance(value, int):
                value = evaluate(value, known, depth + 1)
                if value is None:
                    return None
                known[name] = value
            expr = re.sub(r"\b%s\b" % name, str(value), expr)
    if re.search(r"[A-Za-z_]", expr):
        return None
    try:
        return int(eval(expr, {"__builtins__": {}}))
    except Exception:
        return None


def menu_commands():
    known = {}
    for header in ("menuCmdID.h", "resource.h"):
        path = os.path.join(SRC, header)
        if os.path.exists(path):
            known.update(defines(path))
    rc = open(os.path.join(SRC, "Notepad_plus.rc"), encoding="utf-8", errors="replace").read()
    m = re.search(r"^IDR_[A-Z0-9_]*MENU\s+MENU\b", rc, re.M)
    block = rc[m.start():]
    stack, rows, depth = [], [], 0
    for line in block.splitlines():
        t = line.strip()
        if t == "BEGIN":
            depth += 1
            continue
        if t == "END":
            depth -= 1
            if stack:
                stack.pop()
            if depth <= 0:
                break
            continue
        mp = re.match(r'POPUP\s+"([^"]+)"', t)
        if mp:
            stack.append(mp.group(1).replace("&", ""))
            continue
        mi = re.match(r'MENUITEM\s+"([^"]+)"\s*,\s*(IDM_[A-Z0-9_]+)', t)
        if mi:
            label = mi.group(1).replace("&", "").split("\\t")[0].strip()
            value = evaluate(mi.group(2), known)
            if value is not None:
                rows.append((value, mi.group(2), "/".join(stack), label))
    # Commands the menus build at run time (recent files, the tab menu...)
    # are not in the resource script; english.xml names them by id.
    english = open(os.path.join(SRC, "..", "installer", "nativeLang", "english.xml"),
                   encoding="utf-8", errors="replace").read()
    names = {}
    for ident, label in re.findall(r'<Item (?:id|CMDID)="(\d+)" name="([^"]+)"', english):
        names.setdefault(int(ident), label.replace("&amp;", "&").replace("&", "").split("\\t")[0].strip())
    have = {r[0] for r in rows}
    for name, raw in sorted(known.items()):
        if not name.startswith("IDM_"):
            continue
        value = evaluate(name, known)
        if value is None or value in have or value not in names:
            continue
        rows.append((value, name, "?", names[value]))
        have.add(value)
    return rows, known


VK = {"VK_BACK": 8, "VK_TAB": 9, "VK_RETURN": 13, "VK_ESCAPE": 27, "VK_SPACE": 32,
      "VK_PRIOR": 33, "VK_NEXT": 34, "VK_END": 35, "VK_HOME": 36, "VK_LEFT": 37, "VK_UP": 38,
      "VK_RIGHT": 39, "VK_DOWN": 40, "VK_INSERT": 45, "VK_DELETE": 46, "VK_ADD": 107,
      "VK_SUBTRACT": 109, "VK_DIVIDE": 111, "VK_MULTIPLY": 106, "VK_OEM_1": 186, "VK_OEM_PLUS": 187,
      "VK_OEM_COMMA": 188, "VK_OEM_MINUS": 189, "VK_OEM_PERIOD": 190, "VK_OEM_2": 191,
      "VK_OEM_3": 192, "VK_OEM_4": 219, "VK_OEM_5": 220, "VK_OEM_6": 221, "VK_OEM_7": 222}
for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
    VK["VK_" + c] = ord(c)


def scintilla_ids():
    ids = {}
    for line in open(os.path.join(ROOT, "scintilla", "include", "Scintilla.h"), encoding="utf-8"):
        m = re.match(r"#define\s+(SCI_\w+)\s+(\d+)", line)
        if m:
            ids[m.group(1)] = int(m.group(2))
    return ids


def windows_scintilla_keys(sci, menu_known):
    text = open(os.path.join(SRC, "Parameters.cpp"), encoding="utf-8", errors="replace").read()
    start = text.index("scintKeyDefs[]")
    body = text[start:text.index("};", start)]
    rows = []
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("//"):
            continue
        m = re.match(r'\{L"([^"]*)",\s*(SCI_\w+),\s*(true|false),\s*(true|false),\s*(true|false),\s*(\w+),\s*(\w+)\}', line)
        if not m:
            continue
        name, cmd, ctrl, alt, shift, vk, menu = m.groups()
        if cmd not in sci:
            continue
        vk_value = 0 if vk == "0" else VK.get(vk)
        if vk_value is None:
            continue
        menu_value = 0 if menu == "0" else (evaluate(menu, dict(menu_known)) or 0)
        rows.append((name, sci[cmd], ctrl == "true", alt == "true", shift == "true", vk_value, menu_value))
    return rows


def mac_scintilla_defaults():
    messages = {}
    text = open(os.path.join(ROOT, "scintilla", "include", "ScintillaMessages.h"), encoding="utf-8").read()
    for m in re.finditer(r"^\s*(\w+)\s*=\s*(\d+),", text[text.index("enum class Message"):], re.M):
        messages.setdefault(m.group(1), int(m.group(2)))
    keys = {}
    types = open(os.path.join(ROOT, "scintilla", "include", "ScintillaTypes.h"), encoding="utf-8").read()
    kb = types[types.index("enum class Keys"):]
    for m in re.finditer(r"^\s*(\w+)\s*=\s*(\d+),", kb[:kb.index("};")], re.M):
        keys[m.group(1)] = int(m.group(2))
    SHIFT, CTRL, ALT, META = 1, 2, 4, 16
    mods = {"SCI_NORM": 0, "SCI_SHIFT": SHIFT, "SCI_CTRL": CTRL, "SCI_ALT": ALT, "SCI_META": META,
            "SCI_CSHIFT": CTRL | SHIFT, "SCI_ASHIFT": ALT | SHIFT,
            "SCI_CTRL_META": META, "SCI_SCTRL_META": META | SHIFT}   # OS_X_KEYS
    km = open(os.path.join(ROOT, "scintilla", "src", "KeyMap.cxx"), encoding="utf-8").read()
    body = km[km.index("KeyMap::MapDefault[]"):]
    body = body[:body.index("};")]
    rows = []
    for m in re.finditer(r"\{(Keys::\w+|Key\('(.)'\)|Key\('\\\\(.)'\)),\s*(SCI_\w+),\s*Message::(\w+)\}", body):
        k = m.group(1)
        if k.startswith("Keys::"):
            key = keys.get(k[6:])
        else:
            ch = m.group(2) or m.group(3)
            key = ord(ch)
        mod = mods.get(m.group(4))
        msg = messages.get(m.group(5))
        if key is None or mod is None or msg is None:
            continue
        # Cocoa passes a letter as typed: lower case unless Shift is held.
        if 65 <= key <= 90 and not (mod & SHIFT):
            key += 32
        rows.append((key, mod, msg))
    return rows


def c_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    menus, known = menu_commands()
    sci = scintilla_ids()
    win = windows_scintilla_keys(sci, known)
    mac = mac_scintilla_defaults()
    out = ["// Generated by macos/gen_command_ids.py; do not edit.",
           "// Notepad++'s menu command ids, the Scintilla commands its Shortcut",
           "// Mapper lists, and Scintilla's own macOS default keys.",
           "#pragma once", "",
           "typedef struct { int identifier; const char *name; const char *path; const char *label; } NppMenuCommandID;",
           "static const NppMenuCommandID kNppMenuCommandIDs[] = {"]
    for value, name, path, label in menus:
        out.append("    {%d, %s, %s, %s}," % (value, c_string(name), c_string(path), c_string(label)))
    out += ["};", "static const int kNppMenuCommandIDCount = (int)(sizeof(kNppMenuCommandIDs) / sizeof(kNppMenuCommandIDs[0]));", "",
            "typedef struct { const char *name; int message; int ctrl, alt, shift, vk; int menuCommand; } NppScintillaKeyDefinition;",
            "static const NppScintillaKeyDefinition kNppScintillaKeyDefinitions[] = {"]
    for name, msg, ctrl, alt, shift, vk, menu in win:
        out.append("    {%s, %d, %d, %d, %d, %d, %d}," % (c_string(name), msg, ctrl, alt, shift, vk, menu))
    out += ["};", "static const int kNppScintillaKeyDefinitionCount = (int)(sizeof(kNppScintillaKeyDefinitions) / sizeof(kNppScintillaKeyDefinitions[0]));", "",
            "/// key, SCMOD_* modifiers (on macOS SCMOD_CTRL is Command, SCMOD_META is Control), message.",
            "typedef struct { int key; int modifiers; int message; } NppScintillaDefaultKey;",
            "static const NppScintillaDefaultKey kNppScintillaMacDefaults[] = {"]
    for key, mod, msg in mac:
        out.append("    {%d, %d, %d}," % (key, mod, msg))
    out += ["};", "static const int kNppScintillaMacDefaultCount = (int)(sizeof(kNppScintillaMacDefaults) / sizeof(kNppScintillaMacDefaults[0]));", ""]
    path = os.path.join(HERE, "app", "CommandIDs.h")
    open(path, "w").write("\n".join(out))
    print("%d menu commands, %d Scintilla commands, %d macOS default keys -> %s"
          % (len(menus), len(win), len(mac), os.path.relpath(path, ROOT)))


if __name__ == "__main__":
    main()

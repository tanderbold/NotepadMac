#!/usr/bin/env python3
"""Checks macos/resources/nativeLang-extra: every file is XML, is named after a
nativeLang file, translates only texts english.xml lists, and keeps what must
stay as it is (the ellipsis, <…> markers, product and format names).
Usage: check_nativelang_extra.py [file ...]   (no argument: every file)"""
import os, re, sys
import xml.etree.ElementTree as ET
here = os.path.dirname(os.path.abspath(__file__))
extra = os.path.join(here, "resources", "nativeLang-extra")
native = os.path.join(here, "..", "PowerEditor", "installer", "nativeLang")
master = [i.get("english") for i in ET.parse(os.path.join(extra, "english.xml")).getroot().findall("Item")]
KEEP = ["NotepadMac", "NppExec", "JSON", "XML", "DTD", "XPath", "XSL", "FTP", "Finder", "Notepad++", "Cmd"]
files = sys.argv[1:] or sorted(os.path.join(extra, f) for f in os.listdir(extra) if f.endswith(".xml"))
bad = 0
for path in files:
    name = os.path.basename(path)
    problems = []
    if not os.path.exists(os.path.join(native, name)):
        problems.append("no nativeLang file of this name")
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        print(f"{name}: not XML: {e}"); bad += 1; continue
    if root.tag != "NativeLangExtra":
        problems.append("the root element is not NativeLangExtra")
    seen = set()
    for item in root.findall("Item"):
        en, text = item.get("english"), item.get("text")
        if en not in master:
            problems.append(f"unknown english text: {en!r}"); continue
        if en in seen:
            problems.append(f"twice: {en!r}")
        seen.add(en)
        if not text or not text.strip():
            problems.append(f"empty text for {en!r}"); continue
        if en.endswith("…") != text.endswith("…") and not text.endswith("..."):
            problems.append(f"the ellipsis of {en!r} is not kept: {text!r}")
        if en.startswith("<") != text.startswith("<"):
            problems.append(f"the <…> of {en!r} is not kept: {text!r}")
        for word in KEEP:
            if word in en and word not in text:
                problems.append(f"{word} is gone from {en!r}: {text!r}")
        for placeholder in ("$STR_REPLACE$", "$INT_REPLACE$"):
            if en.count(placeholder) != text.count(placeholder):
                problems.append(f"{placeholder} of {en!r} is not kept: {text!r}")
        # The localiser reads "Group|Field" as two texts; one of ours must not look like that by accident.
        if "|" in text and "|" not in en:
            problems.append(f"a | in {text!r}")
        if "\n" in text or "\t" in text:
            problems.append(f"a line break or tab in {text!r}")
    print(f"{name}: {len(seen)} of {len(master)} texts" + ("" if not problems else f", {len(problems)} problem(s)"))
    for p in problems:
        print("    " + p)
    bad += bool(problems)
sys.exit(1 if bad else 0)

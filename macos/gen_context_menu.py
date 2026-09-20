#!/usr/bin/env python3
"""Writes macos/resources/contextMenu.xml: upstream's default context menu,
taken out of CONTEXTMENU_XML_CONTENT in MISC/Common/NppConstants.h."""
import os, re
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "..", "PowerEditor", "src", "MISC", "Common", "NppConstants.h"), encoding="utf-8").read()
m = re.search(r'CONTEXTMENU_XML_CONTENT\[\] = "\\\n(.*?)";', src, re.S)
text = m.group(1)
text = text.replace("\\r\\n\\\n", "\n").replace('\\"', '"').replace("\\r\\n", "\n")
out = os.path.join(here, "resources", "contextMenu.xml")
open(out, "w", encoding="utf-8").write(text)
print(out, len(text.splitlines()), "lines")

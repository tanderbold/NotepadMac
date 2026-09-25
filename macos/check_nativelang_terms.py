#!/usr/bin/env python3
"""Checks that macos/resources/nativeLang-extra speaks each language's own
nativeLang vocabulary, and the forms the localiser relies on.

The words are learnt from the official files, not listed by hand: every text of
PowerEditor/installer/nativeLang/english.xml is paired with the text of the
same element (the same command id, menu id, control id, attribute) in the
language's file. From the whole-text pairs come phrases ("Function List" ->
"Список функций"); from all pairs, by how often an English word and a word of
the translation go together, come single words ("document" -> "докум…"). An
extra translation whose English has such a term and whose text has none of the
official words for it is reported, with the words the official file uses.

Also reported:
  identical  a text left English where the official file translates its words
             (leave such an Item out: it stays English all the same)
  english    an English word of the source left inside a translated text, which
             the official file never uses in that language
  form       $STR_REPLACE$/$INT_REPLACE$/%@/%d/\\n not kept, an & (the localiser
             reads it as an access key and drops it), a colon or ellipsis the
             English does not have or lacks, a full-width colon where the port
             adds its own, a | (read as Group|Field)

Not failing, counted only: "sense", a term most languages render otherwise than
their official file (the port uses the word in another sense: "Pretty Print" is
no printing), and "loan", an English word a third of the languages keep ("hash").

"form" findings fail. "term", "identical" and "english" findings fail unless
listed in macos/nativelang-terms-pending.txt, the ones a native speaker has to
decide: "file<TAB>english<TAB>kind<TAB>term" to a line, with a fifth column
"right" once one is found to be right as it is.

Usage: check_nativelang_terms.py [-v] [file ...]   (no file: every file)
       -v prints every finding, not only the new ones and the counts
       --pending prints the list as it should now be (to rewrite the file:
       keeps the header and the "right" marks, drops what is no longer found)"""
import collections, os, re, sys
import xml.etree.ElementTree as ET

here = os.path.dirname(os.path.abspath(__file__))
extra_dir = os.path.join(here, "resources", "nativeLang-extra")
native_dir = os.path.join(here, "..", "PowerEditor", "installer", "nativeLang")
pending_path = os.path.join(here, "nativelang-terms-pending.txt")

# Words written as they are in every language (check_nativelang_extra.py's KEEP and the like).
KEEP = {"notepadmac", "notepad", "nppexec", "json", "xml", "dtd", "xpath", "xsl", "ftp", "finder", "cmd",
        "git", "head", "mcp", "http", "https", "curl", "utf", "rtf", "html", "mime", "saml", "url", "rfc",
        "ascii", "hex", "qr", "base64", "base58", "base32", "hmac", "bcrypt", "scrypt", "argon2", "pbkdf2",
        "sha", "kib", "gb", "nppmac", "usr", "local", "bin", "xcode", "select", "install", "don", "ho",
        "markdown", "ai", "pos", "sel", "ln", "col", "pixel", "pixels", "a-z", "rfc1738", "macos", "unix",
        "quoted-printable", "terminal", "xcode-select"}
STOP = set("the a an of to in on for and or with by as is all this that from it be not are no at its into "
           "your you can when what which one two it's do does has have was were been there their them than "
           "then only more most some any each other such own same so too very just also but if "
           # grammar, not terms: modal verbs, time and order words
           "cannot can't could will would want need needs must should may might before after first last new "
           "current again here now yet already still every yes whether how why where who don't doesn't isn't "
           "about over under up down out off".split())
# Scripts written without spaces between words: compared by runs of two or three characters.
NOSPACE = {"chineseSimplified", "taiwaneseMandarin", "hongKongCantonese", "japanese", "thai"}
KEYS = ("id", "menuId", "subMenuId", "CMDID")
PLACEHOLDER = re.compile(r"\$(?:STR|INT)_REPLACE\d?\$")
TOKEN = re.compile(r"[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)*")


def flatten(path):
    """{element path + attribute: text} of a nativeLang file; the path is made of tag
    names and key attributes, so the same key in two languages is the same text."""
    out, seen = {}, set()

    def walk(el, prefix):
        p = prefix + "/" + el.tag + "".join(f"[{a}={el.get(a)}]" for a in KEYS if el.get(a) is not None)
        n = 0
        while f"{p}#{n}" in seen:
            n += 1
        p = f"{p}#{n}"
        seen.add(p)
        for a, v in el.attrib.items():
            if (a in ("name", "value", "message") or a.startswith("title")) and v.strip():
                out[p + "@" + a] = v
        for c in el:
            walk(c, p)
    walk(ET.parse(path).getroot(), "")
    return out


def norm(s):
    """A text as the localiser compares it: no access keys, shortcut, trailing colon or dots."""
    s = re.sub(r"\(&\w\)|&(?=[^&\s])", "", s).replace("&&", "&").split("\t")[0]
    s = re.sub(r"\s+", " ", s).strip()
    return re.sub(r"[\s:：.…。]+$", "", s)


def en_words(s):
    s = PLACEHOLDER.sub(" ", s)
    return [w[:-1] if len(w) > 3 and w.endswith("s") and not w.endswith("ss") and w not in STOP else w
            for w in (x.lower() for x in re.findall(r"[A-Za-z][A-Za-z\-']*[A-Za-z]|[A-Za-z]", s))]


def stem(w):
    w = w.lower()
    return w[:5] if len(w) >= 6 else w[:4] if len(w) >= 4 else w


def words(s):
    return re.findall(r"[^\W\d_](?:[^\W_]|['’-][^\W\d_])*", PLACEHOLDER.sub(" ", s))


def units(s, nospace):
    """What a translated text is compared by: word stems (of a compound's parts too), or
    character runs of 2-3 in a script written without spaces."""
    s = PLACEHOLDER.sub(" ", s)
    if nospace:
        u = set()
        for run in re.findall(r"[\u0e00-\u0e7f\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+", s):
            for n in (2, 3):
                u.update(run[i:i + n] for i in range(len(run) - n + 1))
        u.update(w.lower() for w in re.findall(r"[A-Za-z]{3,}", s))
        return u
    out = set()
    for w in words(s):
        out.add(stem(w))
        if "-" in w:
            out.update(stem(p) for p in w.split("-") if p)
    return out


def text_units(s, nospace):
    """A translated text as has_unit looks into it: its whole words (a compound keeps the
    official word inside it: Leerzeilen) and their parts (d’impronta), or its character runs."""
    if nospace:
        return units(s, True)
    return {p.lower() for w in words(s) for p in [w] + re.split(r"[-'’]", w) if p}


def has_unit(text_units, wanted, nospace):
    """Whether a text has the official word: by its first letters, found anywhere in a word of
    the text or the other way round, so that an ending (новый, новом) or a prefix (the Arabic
    article, an Irish mutation: cluaisín, gcluaisín) does not hide it."""
    if nospace:
        return wanted in text_units
    core = wanted[:max(3, min(4, len(wanted) - 2))]
    return any(core in u or len(u) >= 3 and u[:4] in wanted for u in text_units)


class Vocabulary:
    """What one language's official file says for English words and phrases."""

    def __init__(self, lang, english_flat):
        self.nospace = lang in NOSPACE
        flat = flatten(os.path.join(native_dir, lang + ".xml"))
        self.phrases = collections.defaultdict(collections.Counter)   # "function list" -> {"Список функций": 2}
        self.used = set()                                                # every word the official file uses
        cw, cs, cws = collections.Counter(), collections.Counter(), collections.Counter()
        texts, texts_of_unit = collections.defaultdict(set), collections.defaultdict(set)
        self.forms = collections.defaultdict(collections.Counter)
        for key, en in english_flat.items():
            if key not in flat:
                continue
            a, b = norm(en), norm(flat[key])
            self.used.update(p.lower() for w in words(b) for p in [w] + w.split("-"))
            if not a or not b or a == b or PLACEHOLDER.search(a) and len(words(a)) > 6:
                continue
            # Phrases are the names of things: menu commands and submenus, window and panel titles.
            if 2 <= len(a.split()) <= 4 and ("/Menu/" in key or "@title" in key or "PanelTitle" in key):
                self.phrases[a.lower()][b] += 1
            ew = {w for w in en_words(a) if w not in STOP and len(w) >= 3}
            tu = units(b, self.nospace)
            cw.update(ew)
            cs.update(tu)
            for w in ew:
                texts[w].add(key)
            for u in tu:
                texts_of_unit[u].add(key)
            for w in ew:
                for u in tu:
                    cws[w, u] += 1
            for x in words(b):
                self.forms[stem(x)][x] += 1
        # A word's official translation: the stems that go with it (by Dice's coefficient), as few
        # as cover three quarters of its texts; a word the file renders now one way, now another
        # ("Find": Найти, Искать, Поиск) gets them all, and a word with no steady rendering none.
        by_word = collections.defaultdict(list)
        for (w, u), c in cws.items():
            if c >= 2:
                by_word[w].append((2 * c / (cw[w] + cs[u]), u))
        self.terms = {}
        for w, n in cw.items():
            if n < 4 or w in KEEP:
                continue
            chosen, covered = [], set()
            for d, u in sorted(by_word[w], reverse=True):
                if d < 0.4 or len(chosen) == 3:
                    break
                hit = texts[w] & texts_of_unit[u]
                if len(hit - covered) < 2:
                    continue
                chosen.append(u)
                covered |= hit
                if len(covered) >= 0.75 * n:
                    self.terms[w] = chosen
                    break
        self.phrase_list = sorted(((p, t, [units(x, self.nospace) for x in t]) for p, t in self.phrases.items()
                                   if " " in p), key=lambda x: -len(x[0]))

    def kept(self, w):
        """Whether the official file writes the word as English does (a loan word, a name)."""
        return all(u.isascii() and (u == stem(w) or w.startswith(u)) for u in self.terms[w])

    def shown(self, u):
        return self.forms[u].most_common(1)[0][0] if self.forms.get(u) else u


def form_problems(en, text, colon):
    out = []
    for p in ("$STR_REPLACE$", "$STR_REPLACE1$", "$STR_REPLACE2$", "$INT_REPLACE$", "%@", "%d", "%ld", "\\n", "\n", "\t"):
        if en.count(p) != text.count(p):
            out.append(f"{p!r} is not kept")
    if text.count("&") > en.count("&"):
        out.append("an & (read as an access key and dropped)")
    if "|" in text and "|" not in en:
        out.append("a | (read as Group|Field)")
    e, t = en.rstrip(), text.rstrip()
    if e.endswith(("…", "...")) != t.endswith(("…", "...")):
        out.append("the ellipsis differs from the English")
    if e.endswith(":") != t.endswith((":", "：")):
        out.append("the colon differs from the English")
    elif e.endswith(":") and not t.endswith(colon):
        out.append(f"the colon is not the official file's {colon}")
    return out


def official_colon(lang):
    """The colon the official file ends its labels with: ':' or the full-width '：'."""
    flat, english = flatten(os.path.join(native_dir, lang + ".xml")), flatten(os.path.join(native_dir, "english.xml"))
    c = collections.Counter(flat[k].rstrip()[-1:] for k, v in english.items() if k in flat and v.rstrip().endswith(":"))
    return "：" if c["："] > c[":"] else ":"


def findings_of(path, vocab, colon):
    """[(kind, english, term, detail)] of one file, the (english, term) pairs the term check
    applied to, and the (english, word) pairs whose English word the text keeps."""
    name = os.path.basename(path)
    findings, applied, kept = [], set(), set()
    for item in ET.parse(path).getroot().findall("Item"):
        en, text = item.get("english") or "", item.get("text") or ""
        for p in form_problems(en, text, colon):
            findings.append(("form", en, p, text))
        if name == "english.xml" or vocab is None:
            continue
        ne, nt = norm(en), norm(text)
        ew = [w for w in en_words(ne) if w not in STOP]
        tu = text_units(nt, vocab.nospace)
        if ne == nt:
            translated = sorted({w for w in ew if w in vocab.terms and not vocab.kept(w)})
            if translated:
                findings.append(("identical", en, ", ".join(translated),
                                 "; ".join(f"{w} -> {vocab.shown(vocab.terms[w][0])}" for w in translated)))
            continue
        lower = ne.lower()
        done = set()
        # Phrases first ("Folder as Workspace"), then single words.
        for phrase, translations, phrase_units in vocab.phrase_list:
            if phrase not in lower or not re.search(r"(?<![A-Za-z])" + re.escape(phrase) + r"s?(?![A-Za-z])", lower):
                continue
            done.update(en_words(phrase))
            applied.add((en, phrase))
            if not any(all(has_unit(tu, u, vocab.nospace) for u in us if len(u) >= 2) for us in phrase_units):
                findings.append(("term", en, phrase, "official: " + " / ".join(t for t, _ in translations.most_common(2))
                                 + " | text: " + text))
        for w in dict.fromkeys(ew):
            if w in done or w not in vocab.terms:
                continue
            applied.add((en, w))
            if not any(has_unit(tu, u, vocab.nospace) for u in vocab.terms[w]):
                findings.append(("term", en, w, "official: " + " / ".join(vocab.shown(u) for u in vocab.terms[w][:3])
                                 + " | text: " + text))
        # English left inside a translated text: words of the source, not names, that the
        # official file never uses in this language. In a language written in Latin letters one
        # such word is as likely the language's own (French "image", German "optional"), so there
        # it takes two of them in a row; in any other script one Latin word is enough.
        source = {w.lower() for w in TOKEN.findall(en)}
        letters = re.findall(r"[^\W\d_]", text)
        latin = sum(c.isascii() for c in letters) >= 0.5 * max(1, len(letters))
        tokens = list(re.finditer(r"[^\W\d_]+(?:[-'’][^\W\d_]+)*|\S", PLACEHOLDER.sub("0", text)))
        if len(tokens) > 1:
            left = [t.group() for t in tokens]
            english = [w.lower() in source and TOKEN.fullmatch(w) and len(w) >= 3 and w.lower() not in KEEP
                       and w.lower() not in STOP and w.lower() not in vocab.used and not w.isupper() for w in left]
            kept.update((en, w.lower()) for i, w in enumerate(left) if english[i])
            for i, w in enumerate(left):
                if not english[i]:
                    continue
                if latin and not (i > 0 and english[i - 1] or i + 1 < len(left) and english[i + 1]):
                    continue
                findings.append(("english", en, w, text))
    return findings, applied, kept


def main():
    args = sys.argv[1:]
    report = "-v" in args
    list_pending = "--pending" in args   # the whole pending list, as it should now be
    args = [a for a in args if a not in ("-v", "--pending")]
    wanted = {os.path.basename(a) for a in args}
    everything = sorted(f for f in os.listdir(extra_dir) if f.endswith(".xml"))
    pending, header = {}, []
    if os.path.exists(pending_path):
        for line in open(pending_path, encoding="utf-8"):
            parts = line.rstrip("\n").split("\t")
            if line.startswith("#"):
                header.append(line)
            elif len(parts) in (4, 5):
                pending[tuple(parts[:4])] = parts[4] if len(parts) == 5 else ""
    english_flat = flatten(os.path.join(native_dir, "english.xml"))
    # Every language is read, whatever files are asked for: whether the port's text uses a
    # word in the sense the official files do is told by all of them together.
    per_file, applied_in, flagged_in = {}, collections.Counter(), collections.Counter()
    kept_in, translated_in = collections.Counter(), collections.Counter()
    for name in everything:
        lang = name[:-4]
        has_native = os.path.exists(os.path.join(native_dir, name))
        vocab = Vocabulary(lang, english_flat) if has_native and name != "english.xml" else None
        f, applied, kept = findings_of(os.path.join(extra_dir, name), vocab, official_colon(lang) if has_native else ":")
        per_file[name] = f
        applied_in.update(applied)
        flagged_in.update({(en, term) for kind, en, term, _ in f if kind == "term"})
        kept_in.update(kept)
        translated_in.update({en for kind, en, term, _ in f if kind != "identical"} |
                             {i.get("english") for i in ET.parse(os.path.join(extra_dir, name)).getroot().findall("Item")
                              if norm(i.get("english") or "") != norm(i.get("text") or "")} if vocab else set())
    # A term most languages' translations render otherwise than their official file is a
    # word used in another sense ("Pretty Print" is no printing, "Sort Keys" no keyboard):
    # reported as "sense", for no one to fix.
    def kind_of(kind, en, term):
        if kind == "term" and applied_in[en, term] >= 10 and flagged_in[en, term] >= 0.5 * applied_in[en, term]:
            return "sense"
        # An English word a third of the languages keep in the same text is a loan word of the
        # trade ("hash", "commit", "script"), not something left untranslated.
        if kind == "english" and kept_in[en, term.lower()] >= max(10, translated_in[en] / 3):
            return "loan"
        return kind
    if list_pending:
        # The list rewritten: the header and the "right" marks kept, what is no longer found dropped.
        out = list(header)
        for name in everything:
            for kind, en, term, _ in per_file[name]:
                kind = kind_of(kind, en, term)
                if kind in ("term", "identical", "english"):
                    note = pending.get((name, en, kind, term), "")
                    out.append(f"{name}\t{en}\t{kind}\t{term}" + (f"\t{note}" if note else "") + "\n")
        with open(pending_path, "w", encoding="utf-8") as f:
            f.writelines(out)
        print(f"{os.path.basename(pending_path)}: {len(out) - len(header)} line(s)")
        return
    total, failed = collections.Counter(), 0
    for name in everything:
        if wanted and name not in wanted:
            continue
        counts, lines, new = collections.Counter(), [], 0
        for kind, en, term, detail in per_file[name]:
            kind = kind_of(kind, en, term)
            note = pending.get((name, en, kind, term)) if kind in ("term", "identical", "english") else None
            label = kind if note is None else f"{kind} ({note or 'pending'})"
            counts[label] += 1
            if kind != "sense" and kind != "loan" and note is None:
                new += 1
            if report or (kind not in ("sense", "loan") and note is None):
                lines.append(f"    {label}: {en!r} [{term}] {detail!r}")
        total.update(counts)
        failed += bool(new)
        print(f"{name}: " + (", ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "clean"))
        for line in lines:
            print(line)
    seen = {(n, en, kind_of(k, en, t), t) for n, f in per_file.items() for k, en, t, _ in f}
    stale = [key for key in pending if key not in seen and (not wanted or key[0] in wanted)]
    if stale:
        print(f"{len(stale)} line(s) of {os.path.basename(pending_path)} no longer found (--pending rewrites the list)")
    print("total: " + (", ".join(f"{k} {v}" for k, v in sorted(total.items())) or "clean"))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

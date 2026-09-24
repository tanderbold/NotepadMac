#!/usr/bin/env python3
"""Trains the model that tells a language from a fragment of text.

The application asks one question of it: given what was pasted into an empty
document, or a file with no extension, which languages could this be? The
answer is a set - one language when the text is characteristic, a short list
when it is not, nothing when it narrows nothing down - and the set has to be
right in a measured share of cases, not merely plausible.

    python3 train-language-model.py --linguist ../../linguist --rosetta ../../rosetta
    python3 train-language-model.py --model resources/language-model.bin --try file...

What is learned from: the Linguist samples, Rosetta Code, Lexilla's lexer
examples, the function-list corpus and the repository's own files. Rosetta is
split for testing by task rather than by file, so that two versions of one
program never sit on both sides of the split.

What is learned on: not whole files but pieces of them as well - windows of
three to forty lines - because that is what the model is asked about, and a
model shown only whole files is sure of everything and right about less.

Features are byte n-grams for shape, whole words for vocabulary, and the first
word and the first and last character of each line for syntax. Every feature
is a 64-bit key the application can compute the same way; nothing is looked
up by string.

The model is a linear softmax classifier. Its scores are turned into
probabilities at a scale fitted on held-back fragments, growing with how much
of the text the model recognised, and the set offered is the shortest list of
languages whose probabilities add up to a coverage that was also chosen on
held-back fragments. Nothing in the file was set by eye.

Needs numpy. Nothing else outside the standard library.
"""

import argparse
import collections
import hashlib
import json
import math
import os
import random
import re
import struct
import sys
import time
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def setting(name, default, kind=int):
    return kind(os.environ.get(name, default))


# ---- what a piece of text is measured by -----------------------------------

NGRAM_SIZES = tuple(int(n) for n in os.environ.get("NPP_NGRAMS", "2,3,4").split(","))
TAG_WORD, TAG_FIRST_WORD, TAG_LINE_SHAPE, TAG_WORD_PAIR = 5, 6, 7, 8
WORD_LENGTH, FIRST_WORD_LENGTH, PAIR_WORD_LENGTH = 24, 16, 16

# ---- how much of each file, and how it is cut up ---------------------------

READ_BYTES = 32 * 1024          # read from each file
HEAD_BYTES = 8 * 1024           # the "whole file" example: its beginning
HEAD_LINES = 300
CROPS_PER_FILE = setting("NPP_CROPS", 4)
CROP_LINES = (3, 5, 8, 12, 20, 40)
TEST_LINES = (5, 10, 20, 40)
LEAST_FRAGMENT_BYTES = 40
QUOTING_ONE_IN = setting("NPP_QUOTING_ONE_IN", 3)   # one held-back file in so many also gives a piece that quotes another language

# ---- how much of each language, and from where ------------------------------

VARIED_CAP = setting("NPP_VARIED_CAP", 400)     # Linguist, Lexilla, corpus, repo, repos
ROSETTA_CAP = setting("NPP_ROSETTA_CAP", 150)
ROSETTA_PER_TASK = 2
REPO_FILES_PER_PROJECT = setting("NPP_REPO_FILES", 120)
LEAST_FILES = 3
HOLDOUT = setting("NPP_HOLDOUT", 0.3, float)

# ---- the model --------------------------------------------------------------

FEATURES_PER_LANGUAGE = setting("NPP_PER_LANG", 700)
MOST_FEATURES = setting("NPP_FEATURES", 50000)
LEAST_DF = 3
EPOCHS = setting("NPP_EPOCHS", 15)
BATCH = 256
RATE = setting("NPP_RATE", 0.01, float)
DECAY = setting("NPP_DECAY", 1e-6, float)
MOST_TO_OFFER = 10
SEED = 20260917

# "independent": one yes-or-no judgement per language, so that a text two
# languages could have written scores well for both. "softmax": one choice
# among all, where the two would have to share one probability between them.
MODEL_KIND = os.environ.get("NPP_MODEL", "independent")
POSITIVE_WEIGHT = setting("NPP_POSITIVE", 4.0, float)

SKIP_DIRECTORIES = {".git", "build", "obj", "bin", ".vs", "node_modules"}
SKIP_NAMES = {"SciTE.properties", "Makefile", "makefile", "README", "LICENSE"}
SKIP_EXTENSIONS = {
    "png", "bmp", "ico", "gif", "jpg", "jpeg", "pdf", "zip", "gz", "o", "a",
    "styled", "folded", "result", "exe", "dll", "lib", "pdb", "obj", "bin",
    "ttf", "otf", "icns", "svg",
}

# Two entries in Notepad++'s own list for one language.
SAME_LANGUAGE = {"javascript.js": "javascript"}


# =============================================================================
# The corpus
# =============================================================================

def language_extensions():
    """Extension -> language, from Notepad++'s own list; and every name."""
    path = os.path.join(ROOT, "PowerEditor", "src", "langs.model.xml")
    text = open(path, encoding="utf-8", errors="replace").read()
    by_extension, names = {}, []
    claimants = collections.Counter()
    # (Attributes in whatever order the file has them: Lua's entry puts ext before name.)
    for tag in re.finditer(r'<Language\s[^>]*>', text):
        name_at, ext_at = re.search(r'\bname="([^"]+)"', tag.group(0)), re.search(r'\bext="([^"]*)"', tag.group(0))
        if not name_at or not ext_at:
            continue
        name, extensions = name_at.group(1), ext_at.group(1)
        names.append(name)
        for extension in extensions.split():
            by_extension[extension.lower()] = name
            claimants[extension.lower()] += 1
    # An extension several languages claim - .h is C, C++ and Objective-C -
    # says which of them a file is no better than a coin: such files are not
    # examples of anything.
    language_extensions.ambiguous = {ext for ext, n in claimants.items() if n > 1}
    return by_extension, names


# What Linguist and Rosetta call a language against what Notepad++ calls it.
OTHER_NAMES = {
    "c#": "cs", "c++": "cpp", "objective-c": "objc", "objective-c++": "objc",
    "shell": "bash", "tcsh": "bash", "fish": "bash", "batchfile": "batch",
    "dos batch": "batch", "visual basic": "vb", "visual basic .net": "vb",
    "vb.net": "vb", "vbscript": "vb", "vba": "vb", "basic": "freebasic",
    "javascript": "javascript", "jsx": "javascript",
    "common lisp": "lisp", "emacs lisp": "lisp", "newlisp": "lisp",
    "restructuredtext": "rest", "html+erb": "html", "html+php": "php",
    "html+django": "html", "ocaml": "caml", "standard ml": "caml", "f#": "fsharp",
    "objectscript": "cs", "c2hs haskell": "haskell", "literate haskell": "haskell",
    "fortran": "fortran", "fortran free form": "fortran",
    "fortran fixed form": "fortran77", "gnu fortran": "fortran",
    "matlab": "matlab", "octave": "matlab", "assembly": "asm",
    "motorola 68k assembly": "asm", "x86 assembly": "asm", "unix assembly": "asm",
    "gas": "asm", "text": "normal", "plain text": "normal",
    "sqlpl": "sql", "plsql": "sql", "tsql": "sql", "plpgsql": "sql",
    "inno setup": "inno", "red": "rebol", "windows registry entries": "registry",
    "java server pages": "jsp", "javaserver pages": "jsp",
    # As Rosetta Code spells them.
    "c sharp": "cs", "c plus plus": "cpp", "unix shell": "bash",
    "bbc basic": "freebasic", "objective c": "objc", "free pascal": "pascal",
    "delphi": "pascal", "batch file": "batch", "windows batch file": "batch",
    "f sharp": "fsharp", "python 3": "python", "python 2": "python",
    # Linguist's "JSON with Comments" is JSONC, which Notepad++ opens with its json5
    # lexer (langs.model.xml: json5 ext="json5 jsonc").
    "json with comments": "json5",
}


def language_called(entry, known):
    lowered = entry.lower()
    if lowered in OTHER_NAMES:
        name = OTHER_NAMES[lowered]
        return name if name in known else None
    squeezed = re.sub(r"[^a-z0-9+#]", "", lowered)
    for candidate in (lowered, squeezed):
        if candidate in known:
            return candidate
    return None


def read_sample(path):
    try:
        with open(path, "rb") as handle:
            raw = handle.read(READ_BYTES)
    except OSError:
        return None
    if b"\x00" in raw:
        return None
    return raw


JSON_COMMENT = re.compile(rb"(^|\n)[ \t]*//|/\*")


def is_json(raw):
    """A file labelled JSON is kept only if it is JSON: a tsconfig.json or a
    .vscode/settings.json with comments or trailing commas is JSONC (what Notepad++'s
    json5 lexer is for), and teaching the model that JSON has comments is what made
    it take JSON5 for JSON. A file cut at READ_BYTES cannot be parsed whole: it is
    kept unless it has comments."""
    if len(raw) >= READ_BYTES:
        return not JSON_COMMENT.search(raw)
    try:
        json.loads(raw.decode("utf-8-sig"))
        return True
    except (ValueError, UnicodeDecodeError):
        return False


class Sample:
    __slots__ = ("language", "raw", "path", "source", "group")

    def __init__(self, language, raw, path, source, group):
        self.language = SAME_LANGUAGE.get(language, language)
        # A file of the checkout goes by its path in the repository: the split and the
        # order hash these, and the same checkout elsewhere (a worktree) must train
        # the same model.
        self.raw, self.path, self.source, self.group = raw, in_repository(path), source, in_repository(group)


def in_repository(path):
    full = os.path.abspath(path)
    return os.path.relpath(full, ROOT) if full.startswith(ROOT + os.sep) else path


def gather(by_extension, names, linguist, rosetta, repos=None):
    known = set(names)
    samples = []

    def extension_of(name):
        return name.rsplit(".", 1)[-1].lower() if "." in name else ""

    if linguist:
        samples_root = os.path.join(linguist, "samples")
        for entry in sorted(os.listdir(samples_root)) if os.path.isdir(samples_root) else []:
            directory = os.path.join(samples_root, entry)
            language = language_called(entry, known) if os.path.isdir(directory) else None
            if not language:
                continue
            for walked, subdirectories, files in os.walk(directory):
                subdirectories[:] = [d for d in subdirectories if d not in SKIP_DIRECTORIES]
                for name in files:
                    if extension_of(name) in SKIP_EXTENSIONS:
                        continue
                    path = os.path.join(walked, name)
                    raw = read_sample(path)
                    if raw:
                        samples.append(Sample(language, raw, path, "linguist", path))

    if rosetta:
        languages_root = os.path.join(rosetta, "Lang")
        for entry in sorted(os.listdir(languages_root)) if os.path.isdir(languages_root) else []:
            language = language_called(entry.replace("-", " "), known)
            if not language:
                continue
            language_dir = os.path.join(languages_root, entry)
            for task in sorted(os.listdir(language_dir)):
                task_dir = os.path.join(language_dir, task)
                if not os.path.isdir(task_dir):
                    continue
                taken = 0
                for name in sorted(os.listdir(task_dir)):
                    if name.startswith("00-") or extension_of(name) in SKIP_EXTENSIONS:
                        continue
                    path = os.path.join(task_dir, name)
                    if not os.path.isfile(path):
                        continue
                    raw = read_sample(path)
                    if raw and len(raw) > 120:
                        samples.append(Sample(language, raw, path, "rosetta", task))
                        taken += 1
                    if taken >= ROSETTA_PER_TASK:
                        break

    examples = os.path.join(ROOT, "lexilla", "test", "examples")
    for lexer in sorted(os.listdir(examples)) if os.path.isdir(examples) else []:
        directory = os.path.join(examples, lexer)
        if not os.path.isdir(directory):
            continue
        for name in sorted(os.listdir(directory)):
            if extension_of(name) in SKIP_EXTENSIONS or name in SKIP_NAMES:
                continue
            path = os.path.join(directory, name)
            if not os.path.isfile(path):
                continue
            language = lexer if lexer in known else by_extension.get(extension_of(name))
            if not language:
                continue
            raw = read_sample(path)
            if raw:
                samples.append(Sample(language, raw, path, "lexilla", path))

    corpus = os.path.join(HERE, "resources", "functionList-corpus")
    for entry in sorted(os.listdir(corpus)) if os.path.isdir(corpus) else []:
        language = entry[4:] if entry.startswith("udl-") else entry
        if language not in known:
            continue
        path = os.path.join(corpus, entry, "unitTest")
        raw = read_sample(path)
        if raw:
            samples.append(Sample(language, raw, path, "corpus", path))

    # Real-world repositories (fetch-language-corpus.py): what people write and
    # paste - classes, enums, handlers, configuration. By extension, as
    # Notepad++ takes a file.
    if repos:
        skip = SKIP_DIRECTORIES | {"vendor", "third_party", "thirdparty", "dist", "out", "target", "testdata", "fixtures",
                                   "__pycache__", ".github", "docs", "doc"}
        for project in sorted(os.listdir(repos)) if os.path.isdir(repos) else []:
            base = os.path.join(repos, project)
            if not os.path.isdir(base):
                continue
            per_language = collections.Counter()
            for walked, subdirectories, files in os.walk(base):
                subdirectories[:] = sorted(d for d in subdirectories if d not in skip and not d.startswith("."))
                for name in sorted(files):
                    extension = extension_of(name)
                    # The files Notepad++ knows by name rather than by extension.
                    by_name = {"makefile": "makefile", "gnumakefile": "makefile", "cmakelists.txt": "cmake"}.get(name.lower())
                    if by_name and by_name in names:
                        extension, language = "", by_name
                    elif not extension or extension in SKIP_EXTENSIONS:
                        continue
                    else:
                        language = by_extension.get(extension)
                    if extension == "tex":
                        # Two languages share .tex; a LaTeX file says so in its first lines.
                        head = read_sample(os.path.join(walked, name)) or b""
                        language = "latex" if (b"\\documentclass" in head or b"\\begin{" in head or b"\\usepackage" in head) else "tex"
                    elif extension in language_extensions.ambiguous:
                        continue
                    # Not more of one project than of the others: a big one would be the language.
                    if not language or per_language[language] >= REPO_FILES_PER_PROJECT:
                        continue
                    path = os.path.join(walked, name)
                    raw = read_sample(path)
                    if raw and len(raw) > 200:
                        per_language[language] += 1
                        # Split by folder: a project wholly on one side would leave some
                        # language with no real code to learn from.
                        samples.append(Sample(language, raw, path, "repos", walked))

    # Examples written for the languages no corpus has (language-samples/<name>/),
    # and the hex formats, which are mechanical enough to generate.
    written = os.path.join(HERE, "resources", "language-samples")
    for language in sorted(os.listdir(written)) if os.path.isdir(written) else []:
        directory = os.path.join(written, language)
        if language not in known or not os.path.isdir(directory):
            continue
        for name in sorted(os.listdir(directory)):
            path = os.path.join(directory, name)
            raw = read_sample(path) if os.path.isfile(path) else None
            if raw:
                samples.append(Sample(language, raw, path, "samples", path))
    for language, raw, path in generated_hex(known):
        samples.append(Sample(language, raw, path, "generated", path))

    for directory, subdirectories, files in os.walk(ROOT):
        subdirectories[:] = [d for d in subdirectories if d not in SKIP_DIRECTORIES]
        for name in files:
            extension = extension_of(name)
            if not extension or extension in SKIP_EXTENSIONS:
                continue
            if extension in language_extensions.ambiguous:
                continue
            language = by_extension.get(extension)
            if not language:
                continue
            path = os.path.join(directory, name)
            raw = read_sample(path)
            if raw:
                samples.append(Sample(language, raw, path, "repo", path))

    return [sample for sample in samples if sample.language != "json" or is_json(sample.raw)]


def generated_hex(known, files=12):
    """Intel HEX, Motorola S-records and Tektronix hex, with right checksums:
    firmware images of a few hundred bytes to a few kilobytes."""
    rng = random.Random(SEED)
    out = []

    def data_records(size, width):
        address = rng.choice((0, 0x100, 0x8000, 0x08000000 & 0xFFFF))
        for offset in range(0, size, width):
            chunk = bytes(rng.randrange(256) if rng.random() < 0.8 else 0xFF
                          for _ in range(min(width, size - offset)))
            yield address + offset, chunk

    for n in range(files):
        size, width = rng.randrange(200, 3000), rng.choice((16, 32))
        if "ihex" in known:
            lines = []
            if rng.random() < 0.5:
                lines.append(":020000040800F2")
            for address, chunk in data_records(size, width):
                body = bytes([len(chunk), (address >> 8) & 0xFF, address & 0xFF, 0]) + chunk
                lines.append(":" + body.hex().upper() + f"{(-sum(body)) & 0xFF:02X}")
            lines.append(":00000001FF")
            out.append(("ihex", ("\r\n" if n % 2 else "\n").join(lines).encode() + b"\n", f"generated/ihex/{n}"))
        if "srec" in known:
            lines = []
            header = b"\x00\x00" + f"firmware_{n}.bin".encode()
            body = bytes([len(header) + 1]) + header
            lines.append("S0" + body.hex().upper() + f"{(~sum(body)) & 0xFF:02X}")
            count = 0
            for address, chunk in data_records(size, width):
                body = bytes([len(chunk) + 3, (address >> 8) & 0xFF, address & 0xFF]) + chunk
                lines.append("S1" + body.hex().upper() + f"{(~sum(body)) & 0xFF:02X}")
                count += 1
            body = bytes([3, (count >> 8) & 0xFF, count & 0xFF])
            lines.append("S5" + body.hex().upper() + f"{(~sum(body)) & 0xFF:02X}")
            lines.append("S9030000FC")
            out.append(("srec", "\n".join(lines).encode() + b"\n", f"generated/srec/{n}"))
        if "tehex" in known:
            lines = []
            for address, chunk in data_records(size, rng.choice((16, 30))):
                fields = "6" + "4" + f"{address & 0xFFFF:04X}" + chunk.hex().upper()
                length = len(fields) + 4                      # the two length and two checksum digits
                digits = f"{length:02X}" + fields
                check = sum(int(c, 16) for c in digits) & 0xFF
                lines.append("%" + f"{length:02X}" + fields[0] + f"{check:02X}" + fields[1:])
            end = "8" + "4" + "0000"
            digits = f"{len(end) + 4:02X}" + end
            lines.append("%" + f"{len(end) + 4:02X}" + end[0] + f"{sum(int(c, 16) for c in digits) & 0xFF:02X}" + end[1:])
            out.append(("tehex", "\n".join(lines).encode() + b"\n", f"generated/tehex/{n}"))
    return out


def stable_hash(text):
    return int(hashlib.md5(text.encode("utf-8", "replace")).hexdigest()[:8], 16)


def choose(samples):
    """Which files to use, and which side of the split each is on.

    Duplicates go. Each language takes the varied sources first - they are
    what real files look like - and Rosetta Code only to fill up. The split
    is by group: a Rosetta task or a file path, so that two versions of one
    program are never on both sides.
    """
    seen, unique = set(), []
    for sample in samples:
        digest = hashlib.md5(normalise(sample.raw[:2048])).digest()
        if digest in seen:
            continue
        seen.add(digest)
        unique.append(sample)

    by_language = collections.defaultdict(list)
    for sample in unique:
        by_language[sample.language].append(sample)

    train, test = [], []
    composition = {}
    for language, items in sorted(by_language.items()):
        varied = [s for s in items if s.source != "rosetta"]
        rosetta = [s for s in items if s.source == "rosetta"]
        varied.sort(key=lambda s: stable_hash(s.path))
        rosetta.sort(key=lambda s: stable_hash(s.path))
        chosen = varied[:VARIED_CAP] + rosetta[:ROSETTA_CAP]
        if len(chosen) < LEAST_FILES:
            continue
        composition[language] = collections.Counter(s.source for s in chosen)
        for sample in chosen:
            # The samples written for the application (language-samples) are few and
            # made to show each language as it is: always learnt from, never held back.
            held = sample.source != "samples" and stable_hash("split:" + sample.group) % 1000 < HOLDOUT * 1000
            (test if held else train).append(sample)
    return train, test, composition


# =============================================================================
# Features
# =============================================================================

_RUNS = re.compile(rb"[ \t]+")
_DIGITS = re.compile(rb"[0-9]+")
_WORD = re.compile(rb"[A-Za-z_][A-Za-z0-9_]*")


def normalise(raw):
    """Line endings to LF, runs of blanks to one space, numbers to one zero."""
    raw = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return _DIGITS.sub(b"0", _RUNS.sub(b" ", raw))


def shape_of(byte):
    """A letter, a digit, or the character itself."""
    if 65 <= byte <= 90 or 97 <= byte <= 122 or byte == 95:
        return 97
    if 48 <= byte <= 57:
        return 48
    return byte if byte < 128 else 128


_key_memo = {}


def keyed(tag, token):
    """The 64-bit key of a word or shape: the tag, a CRC of the bytes, and the
    length, which the application computes the same way."""
    key = _key_memo.get((tag, token))
    if key is None:
        key = (tag << 56) | (zlib.crc32(token) << 8) | (len(token) & 0xFF)
        _key_memo[(tag, token)] = key
    return key


def feature_keys(norm):
    """Every feature of a normalised piece of text, with how often it occurs.

    Byte n-grams are packed into the key itself: the size in the top byte and
    the bytes below it. Words and line shapes are hashed.
    """
    bytes_ = np.frombuffer(norm, dtype=np.uint8).astype(np.uint64)
    parts = []
    for size in NGRAM_SIZES:
        n = len(bytes_) - size + 1
        if n <= 0:
            continue
        packed = np.zeros(n, dtype=np.uint64)
        for j in range(size):
            packed = (packed << np.uint64(8)) | bytes_[j:j + n]
        packed |= np.uint64(size) << np.uint64(56)
        parts.append(packed)

    other = []
    for word in _WORD.findall(norm):
        other.append(keyed(TAG_WORD, word[:WORD_LENGTH]))
    for line in norm.split(b"\n"):
        line = line.strip(b" ")
        if not line:
            continue
        other.append(keyed(TAG_LINE_SHAPE, bytes((shape_of(line[0]), shape_of(line[-1])))))
        match = _WORD.match(line)
        if match:
            other.append(keyed(TAG_FIRST_WORD, match.group(0)[:FIRST_WORD_LENGTH]))
        # Neighbouring words of a line: "public enum", "let mut", "end function".
        # One word is shared by a dozen languages where the pair belongs to two.
        tokens = _WORD.findall(line)
        for first, second in zip(tokens, tokens[1:]):
            other.append(keyed(TAG_WORD_PAIR, first[:PAIR_WORD_LENGTH] + b" " + second[:PAIR_WORD_LENGTH]))
    if other:
        parts.append(np.array(other, dtype=np.uint64))
    if not parts:
        return np.zeros(0, np.uint64), np.zeros(0, np.uint32)
    keys, counts = np.unique(np.concatenate(parts), return_counts=True)
    return keys, counts.astype(np.uint32)


# =============================================================================
# Examples: whole heads and windows cut from files
# =============================================================================

class Example:
    __slots__ = ("label", "keys", "counts", "kind", "source", "path", "idx", "val", "evidence")

    def __init__(self, label, norm, kind, source, path):
        self.label, self.kind, self.source, self.path = label, kind, source, path
        self.keys, self.counts = feature_keys(norm)
        self.idx = self.val = None
        self.evidence = 0


def head_of(norm):
    head = norm[:HEAD_BYTES]
    cut = head.rfind(b"\n")
    if cut > HEAD_BYTES // 2:
        head = head[:cut]
    return b"\n".join(head.split(b"\n")[:HEAD_LINES])


def windows(norm, lengths, rng):
    """Pieces of `lengths` lines each, cut from anywhere in the text."""
    lines = norm.split(b"\n")
    if len(lines) < 3:
        return []
    out = []
    for length in lengths:
        for _ in range(6):
            start = rng.randrange(0, max(1, len(lines) - length + 1))
            piece = b"\n".join(lines[start:start + length])
            solid = piece.replace(b" ", b"").replace(b"\n", b"")
            filled = sum(1 for l in lines[start:start + length] if l.strip())
            if len(solid) >= LEAST_FRAGMENT_BYTES and filled >= min(2, length):
                out.append((length, piece))
                break
    return out


def quoting(norm, guest, rng):
    """A piece of one text with a block of another set into it: a script that
    writes out a configuration file, a program with a query in it. Code quotes
    other languages all the time, and what it is does not change when it does -
    even when, as with a unit file written out by a few lines of script, there
    is rather more of the block than of what is around it."""
    host, other = norm.split(b"\n"), guest.split(b"\n")
    length = rng.choice((8, 12, 18, 26))
    start = rng.randrange(0, max(1, len(host) - length + 1))
    piece = host[start:start + length]
    own = sum(1 for line in piece if line.strip())
    if own < 4:
        return None
    take = rng.randrange(2, own + own // 2 + 1)
    begin = rng.randrange(0, max(1, len(other) - take + 1))
    block = [line for line in other[begin:begin + take]]
    if sum(1 for line in block if line.strip()) < 2:
        return None
    at = rng.randrange(1, len(piece))
    return b"\n".join(piece[:at] + block + piece[at:])


def make_examples(samples, label_of, training):
    examples = []
    for i, sample in enumerate(samples):
        norm = normalise(sample.raw)
        label = label_of[sample.language]
        # Measured, not learnt from. Learning from such pieces was tried: the first choice hardly moved
        # (61% to 63% right on these, ordinary pieces the same) and what grew was the lists - offered for
        # 60% of five-line pieces instead of 47%. A bag of features has no way to tell a quotation from
        # the text around it; the row in the report is there so that whatever replaces it can be held to this.
        if not training and stable_hash("quoting:" + sample.path) % QUOTING_ONE_IN == 0 and len(samples) > 1:
            rng = random.Random(stable_hash("quote:" + sample.path))
            guest = samples[rng.randrange(len(samples))]
            if guest.language != sample.language:
                mixed = quoting(norm, normalise(guest.raw), rng)
                if mixed:
                    examples.append(Example(label, mixed, "quoting", sample.source, sample.path))
        examples.append(Example(label, head_of(norm), "head", sample.source, sample.path))
        rng = random.Random(stable_hash("crop:" + sample.path))
        if training:
            wanted = [CROP_LINES[(stable_hash(sample.path) + k) % len(CROP_LINES)]
                      for k in range(CROPS_PER_FILE)]
        else:
            wanted = TEST_LINES
        for length, piece in windows(norm, wanted, rng):
            examples.append(Example(label, piece, length, sample.source, sample.path))
        if (i + 1) % 2000 == 0:
            print(f"    {i + 1}/{len(samples)} files", flush=True)
    return examples


# =============================================================================
# Choosing features and weighting them
# =============================================================================

def choose_features(examples, languages):
    """The keys worth keeping: for each language, the ones far more often
    present in its examples than in everyone else's."""
    per_language = collections.defaultdict(list)
    for example in examples:
        per_language[example.label].append(example.keys)

    all_keys, all_df = [], []
    language_df = {}
    for label, arrays in per_language.items():
        keys, df = np.unique(np.concatenate(arrays), return_counts=True)
        language_df[label] = (keys, df, len(arrays))
        all_keys.append(keys)
        all_df.append(df)
    keys_everywhere, first = np.unique(np.concatenate(all_keys), return_inverse=True)
    df_everywhere = np.zeros(len(keys_everywhere), dtype=np.int64)
    np.add.at(df_everywhere, first, np.concatenate(all_df))
    documents = len(examples)

    best = {}
    for label, (keys, df, count) in language_df.items():
        at = np.searchsorted(keys_everywhere, keys)
        total = df_everywhere[at]
        mine = df / count
        theirs = (total - df) / max(1, documents - count)
        score = mine * np.log((mine + 1e-4) / (theirs + 1e-4))
        usable = (df >= 2) & (total >= LEAST_DF) & (score > 0)
        order = np.argsort(-score[usable])[:FEATURES_PER_LANGUAGE]
        for key, value in zip(keys[usable][order], score[usable][order]):
            if best.get(int(key), 0) < value:
                best[int(key)] = value
    chosen = sorted(best, key=lambda k: -best[k])[:MOST_FEATURES]
    vocabulary = np.array(sorted(chosen), dtype=np.uint64)
    at = np.searchsorted(keys_everywhere, vocabulary)
    idf = (np.log(documents / (1.0 + df_everywhere[at])) + 1.0).astype(np.float32)
    return vocabulary, idf


def vectorise(examples, vocabulary, idf):
    for example in examples:
        at = np.searchsorted(vocabulary, example.keys)
        at[at == len(vocabulary)] = 0
        hit = vocabulary[at] == example.keys
        idx = at[hit].astype(np.int32)
        val = (np.log1p(example.counts[hit]) * idf[idx]).astype(np.float32)
        length = math.sqrt(float(val @ val)) or 1.0
        example.idx, example.val, example.evidence = idx, val / length, len(idx)
        example.keys = example.counts = None       # no longer needed; heads are large


# =============================================================================
# The model
# =============================================================================

def dense(batch, features):
    X = np.zeros((len(batch), features), dtype=np.float32)
    rows = np.repeat(np.arange(len(batch)), [len(e.idx) for e in batch])
    X[rows, np.concatenate([e.idx for e in batch])] = np.concatenate([e.val for e in batch])
    return X


def train(examples, classes, features):
    """Softmax regression by Adam over mini-batches, each example weighted so
    that a language with few files is not drowned by one with many."""
    counts = collections.Counter(e.label for e in examples)
    median = float(np.median(list(counts.values())))
    weight = {label: min(4.0, max(0.25, math.sqrt(median / n))) for label, n in counts.items()}

    W = np.zeros((classes, features), dtype=np.float32)
    b = np.zeros(classes, dtype=np.float32)
    mW, vW = np.zeros_like(W), np.zeros_like(W)
    mb, vb = np.zeros_like(b), np.zeros_like(b)
    beta1, beta2, eps = 0.9, 0.999, 1e-8
    step = 0
    rng = random.Random(SEED)
    order = list(range(len(examples)))
    for epoch in range(EPOCHS):
        rng.shuffle(order)
        loss_total = 0.0
        for start in range(0, len(order), BATCH):
            batch = [examples[i] for i in order[start:start + BATCH]]
            X = dense(batch, features)
            y = np.array([e.label for e in batch])
            w = np.array([weight[e.label] for e in batch], dtype=np.float32)
            S = X @ W.T + b
            rows = np.arange(len(batch))
            if MODEL_KIND == "independent":
                P = 1.0 / (1.0 + np.exp(-S))
                loss_total += float(-(w * np.log(P[rows, y] + 1e-12)).sum())
                Y = np.zeros_like(P)
                Y[rows, y] = 1.0
                P -= Y
                P *= w[:, None] / len(batch)
                P[rows, y] *= POSITIVE_WEIGHT
            else:
                S -= S.max(axis=1, keepdims=True)
                P = np.exp(S)
                P /= P.sum(axis=1, keepdims=True)
                loss_total += float(-(w * np.log(P[rows, y] + 1e-12)).sum())
                P[rows, y] -= 1.0
                P *= w[:, None] / len(batch)
            gW = P.T @ X + DECAY * W
            gb = P.sum(axis=0)
            step += 1
            for param, grad, m, v in ((W, gW, mW, vW), (b, gb, mb, vb)):
                m *= beta1
                m += (1 - beta1) * grad
                v *= beta2
                v += (1 - beta2) * grad * grad
                mhat = m / (1 - beta1 ** step)
                vhat = v / (1 - beta2 ** step)
                param -= RATE * mhat / (np.sqrt(vhat) + eps)
        print(f"    epoch {epoch + 1}/{EPOCHS}  loss {loss_total / len(order):.4f}", flush=True)
    return W, b


def scores_of(examples, W, b):
    out = np.zeros((len(examples), W.shape[0]), dtype=np.float32)
    for start in range(0, len(examples), 1024):
        batch = examples[start:start + 1024]
        out[start:start + len(batch)] = dense(batch, W.shape[1]) @ W.T + b
    return out


def probabilities(scores, evidence, temperature, half):
    scale = temperature * evidence / (evidence + half)
    z = scores * scale[:, None]
    if MODEL_KIND == "independent":
        return 1.0 / (1.0 + np.exp(-z))
    z -= z.max(axis=1, keepdims=True)
    p = np.exp(z)
    p /= p.sum(axis=1, keepdims=True)
    return p


def sorted_probabilities(scores, evidence, temperature, half):
    p = probabilities(scores, evidence, temperature, half)
    order = np.argsort(-p, axis=1)
    return order, np.take_along_axis(p, order, axis=1)


# A lone language below this is offered with the next best, as a short list,
# rather than applied: fitted after the level, 0 until then.
SINGLE_LEVEL = 0.0
SHORT_LIST = 3


def set_sizes(sorted_p, coverage, single=None):
    """How many languages each row offers: with independent judgements,
    those that reach the level; with one shared probability, the fewest whose
    probabilities add up to it. Zero is possible only with the former. A lone
    language not sure enough to be applied becomes a short list."""
    if MODEL_KIND == "independent":
        size = (sorted_p >= coverage - 1e-9).sum(axis=1)
        single = SINGLE_LEVEL if single is None else single
        unsure = (size == 1) & (sorted_p[:, 0] < single - 1e-9)
        return np.where(unsure, min(SHORT_LIST, sorted_p.shape[1]), size)
    reached = np.cumsum(sorted_p, axis=1) >= coverage - 1e-9
    return reached.argmax(axis=1) + 1


def offered(p, coverage):
    """Each row's offered set: the fewest languages, best first, whose
    probabilities reach `coverage`. Returns the order and each row's size."""
    order = np.argsort(-p, axis=1)
    return order, set_sizes(np.take_along_axis(p, order, axis=1), coverage)


def contains(order, size, labels):
    rank = np.argmax(order == labels[:, None], axis=1)
    return rank < size


# What a list costs against a miss. A list is a dialog the user has to answer;
# a miss is the wrong language applied or none at all. One miss is taken to be
# as bad as six or seven lists.
LIST_COST = setting("NPP_LIST_COST", 0.15, float)
TEMPERATURES = np.geomspace(0.05, 10.0, 40)
HALVES = (0.0, 25.0, 50.0, 100.0, 200.0, 400.0, 800.0, 1600.0)
# Walked so that each step only lengthens the sets.
COVERAGES = (np.arange(0.95, 0.04, -0.01) if MODEL_KIND == "independent"
             else np.arange(0.50, 0.995, 0.01))


def fit_rule(scores, evidence, labels, weights):
    """The scale, its growth with evidence, and the level, chosen together
    for what they are used for: the offered set should hold the right
    language as often as it can, and be a list as rarely as it can while it
    does. Fitting the scale by likelihood first and the level after gives a
    rule that is sure where it is wrong; this fits the rule itself."""
    total = float(weights.sum())
    best = None
    for half in HALVES:
        for temperature in TEMPERATURES:
            order, sorted_p = sorted_probabilities(scores, evidence, temperature, half)
            rank = np.argmax(order == labels[:, None], axis=1)
            for coverage in COVERAGES:
                size = set_sizes(sorted_p, coverage)
                inside = float((weights * ((rank < size) & (size <= MOST_TO_OFFER))).sum()) / total
                listed = float((weights * ((size > 1) & (size <= MOST_TO_OFFER))).sum()) / total
                value = inside - LIST_COST * listed
                if best is None or value > best[0]:
                    best = (value, float(temperature), float(half), float(coverage))
    _, temperature, half, coverage = best
    # Then how sure one language has to be to be applied alone, by the same
    # measure: a wrong language applied is a miss, a short list is a list.
    single = coverage
    if MODEL_KIND == "independent":
        order, sorted_p = sorted_probabilities(scores, evidence, temperature, half)
        rank = np.argmax(order == labels[:, None], axis=1)
        best_value = None
        for level in np.arange(coverage, 1.0, 0.005):
            size = set_sizes(sorted_p, coverage, level)
            inside = float((weights * ((rank < size) & (size <= MOST_TO_OFFER))).sum()) / total
            listed = float((weights * ((size > 1) & (size <= MOST_TO_OFFER))).sum()) / total
            value = inside - LIST_COST * listed
            if best_value is None or value > best_value + 1e-9:
                best_value, single = value, float(level)
    return temperature, half, coverage, single


def diagnose(held, scores, temperature, half):
    """How far down the right language sits, and whether the probabilities
    mean what they say."""
    labels = np.array([e.label for e in held])
    evidence = np.array([e.evidence for e in held], dtype=np.float32)
    order, sorted_p = sorted_probabilities(scores, evidence, temperature, half)
    rank = np.argmax(order == labels[:, None], axis=1)
    kinds = ["head"] + list(TEST_LINES) + ["quoting"]
    print(f"\n{'fragment':<10}" + "".join(f"{'in ' + str(k):>8}" for k in (1, 2, 3, 5, 10)))
    for kind in kinds:
        rows = np.array([e.kind == kind for e in held])
        if rows.any():
            label = "whole" if kind == "head" else "quoting" if kind == "quoting" else f"{kind} lines"
            print(f"{label:<10}" + "".join(f"{100 * np.mean(rank[rows] < k):>7.1f}%" for k in (1, 2, 3, 5, 10)))
    if MODEL_KIND == "independent":
        print("\nwhat each level would offer (10- and 20-line fragments):")
        print(f"  {'level':<7}{'in set':>8}{'size':>6}{'one':>7}{'one ok':>8}{'list':>7}{'none':>7}")
        rows = np.array([e.kind in (10, 20) for e in held])
        for level in np.arange(0.15, 0.66, 0.05):
            size = set_sizes(sorted_p[rows], level)
            inside = (rank[rows] < size) & (size <= MOST_TO_OFFER)
            one = size == 1
            print(f"  {level:<7.2f}{100 * inside.mean():>7.1f}%{size.mean():>6.1f}{100 * one.mean():>6.0f}%"
                  f"{100 * (one & (rank[rows] == 0)).sum() / max(1, one.sum()):>7.0f}%"
                  f"{100 * ((size > 1) & (size <= MOST_TO_OFFER)).mean():>6.0f}%"
                  f"{100 * ((size == 0) | (size > MOST_TO_OFFER)).mean():>6.0f}%")
    print("\nhow sure against how often right (fragments):")
    fragments = np.array([e.kind != "head" for e in held])
    top = sorted_p[fragments, 0]
    right = rank[fragments] == 0
    for low, high in ((0, .5), (.5, .7), (.7, .8), (.8, .9), (.9, .95), (.95, .99), (.99, 1.01)):
        rows = (top >= low) & (top < high)
        if rows.any():
            print(f"  {low:.2f}-{min(high, 1):.2f}  {int(rows.sum()):>5}  right {100 * right[rows].mean():.1f}%")


# =============================================================================
# The file
# =============================================================================

MAGIC = b"NPPLANG\x05"


def write_model(path, languages, vocabulary, idf, W, b, temperature, half, coverage, single):
    """
        magic "NPPLANG" 5
        u32 languages, u32 features, u8 n-gram count, u8 flags,
        f32 temperature, f32 half-evidence, f32 coverage, f32 single, n-gram sizes
        each language: u16 length, utf-8 name
        each feature: u64 key, ascending
        each feature: i16 idf in hundredths
        each language: f32 bias
        each language: f32 scale, then i8 weight per feature (weight * 127 / scale)
    """
    with open(path, "wb") as out:
        out.write(MAGIC)
        flags = 1 | (2 if MODEL_KIND == "independent" else 0)
        out.write(struct.pack("<IIBBffff", len(languages), len(vocabulary),
                              len(NGRAM_SIZES), flags, temperature, half, coverage, single))
        out.write(bytes(NGRAM_SIZES))
        for name in languages:
            raw = name.encode("utf-8")
            out.write(struct.pack("<H", len(raw)) + raw)
        out.write(vocabulary.astype("<u8").tobytes())
        out.write(np.clip(np.round(idf * 100.0), -32768, 32767).astype("<i2").tobytes())
        out.write(b.astype("<f4").tobytes())
        for row in W:
            scale = float(np.abs(row).max()) or 1.0
            out.write(struct.pack("<f", scale))
            out.write(np.clip(np.round(row * 127.0 / scale), -127, 127).astype("i1").tobytes())


class Model:
    """A model read back from its file, answering the way the application does."""

    def __init__(self, path):
        data = open(path, "rb").read()
        assert data[:7] == MAGIC[:7] and data[7] in (4, 5), "not a model file"
        at = 8
        layout = "<IIBBffff" if data[7] == 5 else "<IIBBfff"
        fields = struct.unpack_from(layout, data, at)
        classes, features, sizes, flags, self.temperature, self.half, self.coverage = fields[:7]
        self.single = fields[7] if len(fields) > 7 else self.coverage
        global MODEL_KIND, SINGLE_LEVEL
        MODEL_KIND = "independent" if flags & 2 else "softmax"
        SINGLE_LEVEL = self.single
        at += struct.calcsize(layout)
        self.ngram_sizes = tuple(data[at:at + sizes])
        at += sizes
        self.languages = []
        for _ in range(classes):
            (n,) = struct.unpack_from("<H", data, at)
            at += 2
            self.languages.append(data[at:at + n].decode("utf-8"))
            at += n
        self.vocabulary = np.frombuffer(data, dtype="<u8", count=features, offset=at).astype(np.uint64)
        at += 8 * features
        self.idf = np.frombuffer(data, dtype="<i2", count=features, offset=at).astype(np.float32) / 100.0
        at += 2 * features
        self.bias = np.frombuffer(data, dtype="<f4", count=classes, offset=at).astype(np.float32)
        at += 4 * classes
        self.W = np.zeros((classes, features), dtype=np.float32)
        for c in range(classes):
            (scale,) = struct.unpack_from("<f", data, at)
            at += 4
            row = np.frombuffer(data, dtype="i1", count=features, offset=at).astype(np.float32)
            at += features
            self.W[c] = row * scale / 127.0

    def answer(self, raw):
        """Probabilities best first, the evidence, and the set to offer."""
        global NGRAM_SIZES
        NGRAM_SIZES = self.ngram_sizes
        example = Example(0, normalise(raw), "try", "try", "")
        vectorise([example], self.vocabulary, self.idf)
        if not example.evidence:
            return [], 0, []
        scores = scores_of([example], self.W, self.bias)
        p = probabilities(scores, np.array([example.evidence], dtype=np.float32),
                          self.temperature, self.half)[0]
        order = np.argsort(-p)
        cumulative, chosen = 0.0, []
        for i in order:
            if MODEL_KIND == "independent":
                if p[i] < self.coverage - 1e-9:
                    break
                chosen.append(self.languages[i])
                continue
            chosen.append(self.languages[i])
            cumulative += p[i]
            if cumulative >= self.coverage - 1e-9:
                break
        if MODEL_KIND == "independent" and len(chosen) == 1 and p[order[0]] < self.single - 1e-9:
            chosen = [self.languages[i] for i in order[:SHORT_LIST]]
        ranked = [(self.languages[i], float(p[i])) for i in order]
        return ranked, example.evidence, (chosen if len(chosen) <= MOST_TO_OFFER else [])


# =============================================================================
# Reporting
# =============================================================================

def report(held, scores, languages, temperature, half, coverage, by_source=True):
    labels = np.array([e.label for e in held])
    evidence = np.array([e.evidence for e in held], dtype=np.float32)
    p = probabilities(scores, evidence, temperature, half)
    order, size = offered(p, coverage)
    inside = contains(order, size, labels)
    top = order[:, 0] == labels
    kinds = ["head"] + list(TEST_LINES) + ["quoting"]

    print(f"\n{'fragment':<10}{'n':>6}{'first':>8}{'in set':>8}{'size':>6}"
          f"{'one':>7}{'one ok':>8}{'list':>7}{'none':>7}")
    for kind in kinds:
        rows = np.array([e.kind == kind for e in held])
        if not rows.any():
            continue
        n = int(rows.sum())
        one = size[rows] == 1
        listed = (size[rows] > 1) & (size[rows] <= MOST_TO_OFFER)
        none = (size[rows] > MOST_TO_OFFER) | (size[rows] == 0)
        label = "whole" if kind == "head" else "quoting" if kind == "quoting" else f"{kind} lines"
        print(f"{label:<10}{n:>6}{100 * top[rows].mean():>7.1f}%{100 * inside[rows].mean():>7.1f}%"
              f"{size[rows].mean():>6.1f}{100 * one.mean():>6.0f}%"
              f"{100 * (one & top[rows]).mean() / max(1e-9, one.mean()):>7.0f}%"
              f"{100 * listed.mean():>6.0f}%{100 * none.mean():>6.0f}%")

    if by_source:
        print("\nwhole files by source:")
        for source in sorted({e.source for e in held}):
            rows = np.array([e.kind == "head" and e.source == source for e in held])
            if rows.any():
                print(f"  {source:<10}{int(rows.sum()):>5}  {100 * top[rows].mean():.1f}% first, "
                      f"{100 * inside[rows].mean():.1f}% in set")

    confusion = collections.Counter()
    for e, guess, ok in zip(held, order[:, 0], top):
        if e.kind == "head" and not ok:
            confusion[(languages[e.label], languages[guess])] += 1
    print("\nwhole files most often misread:")
    for (want, got), n in confusion.most_common(20):
        print(f"  {want:<14} as {got:<14} {n}")


def show(model, path):
    raw = open(path, "rb").read()
    ranked, evidence, chosen = model.answer(raw)
    print(f"{path}: evidence {evidence}")
    print("  " + "  ".join(f"{name}/{p:.3f}" for name, p in ranked[:8]))
    print("  offered: " + (", ".join(chosen) if chosen else "(nothing)"))


# =============================================================================

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(HERE, "resources", "language-model.bin"))
    parser.add_argument("--rosetta", default="")
    parser.add_argument("--linguist", default="")
    parser.add_argument("--repos", default="", help="a folder of cloned repositories (fetch-language-corpus.py)")
    parser.add_argument("--model", default="", help="read this model instead of training")
    parser.add_argument("--try", dest="try_files", nargs="*", default=[],
                        help="files to classify with the model")
    parser.add_argument("--report", action="store_true", help="what the corpus holds")
    args = parser.parse_args()

    if args.model:
        model = Model(args.model)
        print(f"{len(model.languages)} languages, {len(model.vocabulary)} features, {MODEL_KIND}, "
              f"scale {model.temperature:.2f} at half-evidence {model.half:.0f}, "
              f"level {model.coverage:.2f}")
        for path in args.try_files:
            show(model, path)
        return

    started = time.time()
    by_extension, names = language_extensions()
    print("==> gathering", flush=True)
    samples = gather(by_extension, names, args.linguist or None, args.rosetta or None, args.repos or None)
    train_samples, test_samples, composition = choose(samples)
    languages = sorted(composition)
    label_of = {name: i for i, name in enumerate(languages)}
    print(f"    {len(samples)} files found, {len(train_samples)} to learn from and "
          f"{len(test_samples)} held back, {len(languages)} languages")
    if args.report:
        for language in languages:
            parts = ", ".join(f"{n} {s}" for s, n in sorted(composition[language].items()))
            print(f"    {language:<16} {parts}")
        missing = sorted(set(names) - set(languages))
        print(f"    no examples of {len(missing)}: {', '.join(missing)}")

    print("==> cutting up", flush=True)
    training = make_examples(train_samples, label_of, training=True)
    held = make_examples(test_samples, label_of, training=False)
    print(f"    {len(training)} examples to learn from, {len(held)} to measure with "
          f"({time.time() - started:.0f}s)")

    print("==> choosing features", flush=True)
    vocabulary, idf = choose_features(training, languages)
    vectorise(training, vocabulary, idf)
    vectorise(held, vocabulary, idf)
    training = [e for e in training if e.evidence]
    held = [e for e in held if e.evidence]
    print(f"    {len(vocabulary)} features ({time.time() - started:.0f}s)")

    print("==> training", flush=True)
    W, b = train(training, len(languages), len(vocabulary))

    print("==> fitting the rule", flush=True)
    # Half the held-back files fit the rule, the other half measure it: a rule
    # measured on what it was fitted to flatters itself.
    # (Not the pieces that quote another language: those are there to be measured - see make_examples.)
    calibration = [e for e in held if stable_hash("half:" + e.path) % 2 == 0 and e.kind != "quoting"]
    check = [e for e in held if stable_hash("half:" + e.path) % 2 == 1]
    scores = scores_of(calibration, W, b)
    labels = np.array([e.label for e in calibration])
    evidence = np.array([e.evidence for e in calibration], dtype=np.float32)
    # Rosetta Code is most of what is held back and the least like real files;
    # it counts for less when deciding how sure to be.
    weights = np.array([0.3 if e.source == "rosetta" else 1.0 for e in calibration], dtype=np.float32)
    global SINGLE_LEVEL
    temperature, half, coverage, SINGLE_LEVEL = fit_rule(scores, evidence, labels, weights)
    print(f"    scale {temperature:.2f} at half-evidence {half:.0f}, level {coverage:.2f}, "
          f"alone from {SINGLE_LEVEL:.3f} "
          f"(fitted on {len(calibration)} examples, measured on {len(check)} others)")
    held = check
    scores = scores_of(held, W, b)

    write_model(args.out, languages, vocabulary, idf, W, b, temperature, half, coverage, SINGLE_LEVEL)
    print(f"==> {len(languages)} languages, {len(vocabulary)} features, "
          f"{os.path.getsize(args.out) // 1024} KB -> {args.out} ({time.time() - started:.0f}s)")

    report(held, scores, languages, temperature, half, coverage)
    diagnose(held, scores, temperature, half)

    if args.try_files:
        model = Model(args.out)
        for path in args.try_files:
            show(model, path)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Fetches real-world code for the language model: shallow clones of well-known
open-source repositories, the kind of code people actually paste - classes,
enums, handlers, configuration - which Rosetta Code's puzzles are not.

    python3 macos/fetch-language-corpus.py <folder>
    python3 macos/train-language-model.py --linguist … --rosetta … --repos <folder>

The trainer takes files by their extension, as Notepad++ does, so a repository
listed under one language also gives what else it holds (its JSON, YAML, shell).

A language with no well-known project to clone - INI, KiXtart, a .reg file - is
filled in from GitHub's code search instead: files with its extension, a couple
from each repository they turn up in, so that no one author is the language.
That part needs the gh command, logged in.
"""
import json, os, subprocess, sys, time

REPOSITORIES = {
    "cs":         ["jbogard/MediatR", "JamesNK/Newtonsoft.Json", "dotnet-architecture/eShopOnWeb", "App-vNext/Polly"],
    "java":       ["spring-projects/spring-petclinic", "google/gson", "square/retrofit", "iluwatar/java-design-patterns"],
    "cpp":        ["fmtlib/fmt", "google/leveldb", "gabime/spdlog"],
    "c":          ["jqlang/jq", "antirez/kilo", "redis/hiredis", "libuv/libuv"],
    "python":     ["psf/requests", "pallets/flask", "encode/httpx"],
    "javascript": ["expressjs/express", "axios/axios", "chartjs/Chart.js"],
    "typescript": ["colinhacks/zod", "nestjs/nest", "typeorm/typeorm"],
    "go":         ["gin-gonic/gin", "spf13/cobra", "gorilla/mux"],
    "rust":       ["BurntSushi/ripgrep", "serde-rs/serde", "clap-rs/clap"],
    "php":        ["slimphp/Slim", "guzzle/guzzle", "symfony/console"],
    "ruby":       ["sinatra/sinatra", "jekyll/jekyll", "rack/rack"],
    "swift":      ["Alamofire/Alamofire", "vapor/vapor", "onevcat/Kingfisher"],
    "powershell": ["dahlbyk/posh-git", "pester/Pester", "PowerShell/PSScriptAnalyzer"],
    "bash":       ["nvm-sh/nvm", "dylanaraps/neofetch", "acmesh-official/acme.sh"],
    "sql":        ["jOOQ/sakila", "lerocha/chinook-database"],
    "lua":        ["kikito/middleclass", "rxi/lume", "luvit/luvit"],
    "perl":       ["mojolicious/mojo", "Perl-Critic/Perl-Critic"],
    "objc":       ["AFNetworking/AFNetworking", "SDWebImage/SDWebImage"],
    "haskell":    ["xmonad/xmonad", "haskell/aeson"],
    "r":          ["tidyverse/dplyr", "rstudio/shiny"],
    "vb":         ["dotnet/samples"],
    "pascal":     ["castle-engine/castle-engine"],
    "scheme":     ["ashinn/chibi-scheme"],
    "erlang":     ["ninenines/cowboy"],
    "d":          ["dlang/phobos"],
    "latex":      ["posquit0/Awesome-CV", "HarisIqbal88/PlotNeuralNet", "latex3/latex2e", "jgm/pandoc-templates"],
    "tex":        ["hyphenation/tex-hyphen"],
    "ini":        ["git/git"],
    "makefile":   ["torvalds/uemacs", "mirror/busybox"],
    "cmake":      ["ttroy50/cmake-examples"],
    "yaml":       ["ansible/ansible-examples", "kubernetes/examples"],
    "css":        ["necolas/normalize.css", "jgthms/bulma"],
    "asm":        ["cirosantilli/x86-assembly-cheat", "netwide-assembler/nasm"],
    "nim":        ["nim-lang/Nim"],
    "fortran":    ["fortran-lang/stdlib"],
    "cobol":      ["openmainframeproject/cobol-programming-course"],
    "tcl":        ["tcltk/tcllib"],
    "ada":        ["AdaCore/Ada_Drivers_Library"],
    "caml":       ["ocaml/dune"],
    "lisp":       ["edicl/hunchentoot", "norvig/paip-lisp"],
    "matlab":     ["chebfun/chebfun"],
    "verilog":    ["YosysHQ/picorv32"],
    "vhdl":       ["VUnit/vunit"],
        "nsis":       ["kichik/nsis"],
    "inno":       ["jrsoftware/issrc"],
    "batch":      ["npocmaka/batch.scripts"],
    "coffeescript": ["jashkenas/coffeescript"],
    "smalltalk":  ["pharo-project/pharo-launcher"],
    "gdscript":   ["godotengine/godot-demo-projects"],
    "fsharp":     ["fsprojects/FSharp.Data"],
    "visualprolog": [],
    "asp":        [],
}

# Language -> the extensions to search for. Only the ones that mean that
# language out in the world too: .bas is more often Visual Basic than FreeBASIC,
# .pro more often Qt than Visual Prolog, and such are left out.
SEARCHED = {
    "ini": ["ini", "inf"], "props": ["properties"], "registry": ["reg"], "diff": ["diff", "patch"],
    "inno": ["iss"], "rc": ["rc"], "nfo": ["nfo"], "json5": ["json5"], "jsp": ["jsp"], "asp": ["asp"],
    "actionscript": ["as"], "ada": ["adb", "ads"], "autoit": ["au3"], "avs": ["avs"],
    "cobol": ["cbl", "cob"], "csound": ["orc", "csd"], "forth": ["forth"],
    "fortran77": ["f77"], "hollywood": ["hws"], "kix": ["kix"], "postscript": ["ps"],
    "purebasic": ["pb"], "raku": ["raku", "rakumod"], "rebol": ["reb", "r3"], "sas": ["sas"],
    "txt2tags": ["t2t"], "asn1": ["mib"],
}
FOUND_PER_LANGUAGE = 120
FOUND_PER_REPOSITORY = 2


def search(root):
    for language, extensions in SEARCHED.items():
        have = sum(len(files) for folder in os.listdir(root) if folder.startswith(f"found-{language}__")
                   for _, _, files in os.walk(os.path.join(root, folder)))
        if have >= FOUND_PER_LANGUAGE // 2:
            print("have", language, have); continue
        taken = have
        for extension in extensions:
            for page in (1, 2, 3):
                if taken >= FOUND_PER_LANGUAGE:
                    break
                result = subprocess.run(["gh", "api", "-X", "GET", "search/code", "-f", f"q=extension:{extension}",
                                         "-f", "per_page=100", "-f", f"page={page}"], capture_output=True, text=True)
                time.sleep(7)       # the search allows ten questions a minute
                if result.returncode:
                    print("   search failed:", extension, result.stderr.strip()[:120]); break
                items = json.loads(result.stdout).get("items", [])
                if not items:
                    break
                per_repository = {}
                for item in items:
                    if taken >= FOUND_PER_LANGUAGE:
                        break
                    repository = item["repository"]["full_name"]
                    if per_repository.get(repository, 0) >= FOUND_PER_REPOSITORY:
                        continue
                    folder = os.path.join(root, f"found-{language}__" + repository.replace("/", "__"))
                    if os.path.isdir(folder) and page == 1 and not per_repository.get(repository):
                        continue
                    raw = item["html_url"].replace("https://github.com/", "https://raw.githubusercontent.com/", 1) \
                                          .replace("/blob/", "/", 1)
                    # (curl rather than urllib: it has the system's certificates to hand.)
                    got = subprocess.run(["curl", "-sfL", "--max-time", "20", "--max-filesize", str(300 * 1024), raw],
                                         capture_output=True)
                    if got.returncode:
                        continue
                    data = got.stdout
                    if len(data) < 200 or b"\0" in data[:4096]:
                        continue
                    os.makedirs(folder, exist_ok=True)
                    with open(os.path.join(folder, f"{per_repository.get(repository, 0)}-" + os.path.basename(item["path"])), "wb") as out:
                        out.write(data)
                    per_repository[repository] = per_repository.get(repository, 0) + 1
                    taken += 1
        print("found", language, taken, flush=True)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = os.path.abspath(sys.argv[1])
    os.makedirs(root, exist_ok=True)
    for language, names in REPOSITORIES.items():
        for name in names:
            target = os.path.join(root, name.replace("/", "__"))
            if os.path.isdir(target):
                print("have", name); continue
            print("clone", name, flush=True)
            result = subprocess.run(["git", "clone", "--quiet", "--depth", "1", "--single-branch",
                                     f"https://github.com/{name}.git", target],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            if result.returncode:
                print("   failed:", result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "?")
                continue
            subprocess.run(["rm", "-rf", os.path.join(target, ".git")])
    search(root)

if __name__ == "__main__":
    main()

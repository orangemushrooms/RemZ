"""German catalogue maintenance for RemZ (English is the source language, see scripts/lang.gd).

  python tools/i18n.py merge <fragment.json>...  add {"English": "German"} pairs to godot/locale/de.po
  python tools/i18n.py check                     fail on missing / broken / leftover German text
  python tools/i18n.py review                    English-looking literals without a German entry
  python tools/i18n.py write                     rewrite de.po sorted by where each msgid is used
  check / review take --files=scripts/a.gd,scripts/b.gd (limit the report) and --with=x.json,y.json
  (count fragments that are not merged yet)

check looks for:
  - Lang.t("...") msgids and UI data fields ("name", "desc", ...) without a German translation
  - msgid / msgstr pairs whose %d / %s / %.1f placeholders differ
  - German words left in string literals of godot/scripts (comments, logs and prints excluded)
  - German translations that are themselves an English msgid with another meaning (would be
    translated twice by a label that auto-translates)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.path.join(ROOT, "godot")
PO = os.path.join(GODOT, "locale", "de.po")
ALLOW = os.path.join(ROOT, "tools", "i18n_allow.txt")
HEADER = ('msgid ""\nmsgstr ""\n"Project-Id-Version: RemZ\\n"\n"Language: de\\n"\n'
          '"MIME-Version: 1.0\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n'
          '"Content-Transfer-Encoding: 8bit\\n"\n')

# ---------------------------------------------------------------- PO file
def _po_unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "r": "\r"}.get(n, "\\" + n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _po_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")


def read_po(path=PO):
    """Ordered dict msgid -> msgstr (header skipped)."""
    entries = {}
    if not os.path.exists(path):
        return entries
    key, cur, buf = None, None, {"msgid": "", "msgstr": ""}

    def flush():
        if buf["msgid"]:
            entries[buf["msgid"]] = buf["msgstr"]

    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        m = re.match(r'^(msgid|msgstr|msgctxt)\s+"(.*)"$', line)
        if m:
            if m.group(1) == "msgid":
                flush()
                buf = {"msgid": "", "msgstr": ""}
            cur = m.group(1)
            buf[cur] = buf.get(cur, "") + _po_unescape(m.group(2))
            continue
        m = re.match(r'^"(.*)"$', line)
        if m and cur:
            buf[cur] = buf.get(cur, "") + _po_unescape(m.group(1))
    flush()
    return entries


def write_po(entries, refs, path=PO):
    """Entries in the order of their first use in the code, unused ones last."""
    def order(item):
        where = refs.get(item[0])
        return (0, where[0][0], where[0][1]) if where else (1, "", 0)

    lines = [HEADER]
    for msgid, msgstr in sorted(entries.items(), key=order):
        lines.append("")
        where = refs.get(msgid)
        if where:
            files = []
            for f, _ in where:
                if f not in files:
                    files.append(f)
            lines.append("#: " + " ".join(files[:4]))
        else:
            lines.append("#. unused")
        lines.append('msgid "%s"' % _po_escape(msgid))
        lines.append('msgstr "%s"' % _po_escape(msgstr))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

# ---------------------------------------------------------------- GDScript literals
_ESC = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "0": "\0", "a": "\a", "b": "\b",
        "f": "\f", "v": "\v"}


def _gd_unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n == "u" and i + 5 < len(s) + 1:
                try:
                    out.append(chr(int(s[i + 2:i + 6], 16)))
                    i += 6
                    continue
                except ValueError:
                    pass
            if n == "U":
                try:
                    out.append(chr(int(s[i + 2:i + 8], 16)))
                    i += 8
                    continue
                except ValueError:
                    pass
            out.append(_ESC.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def literals(src):
    """(line, text, prefix_on_line, is_triple) for every string literal outside comments."""
    i, n, line = 0, len(src), 1
    line_start = 0
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            line_start = i
            continue
        if c == "#":
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if c in "\"'":
            q = c
            marker = src[i - 1] if i > 0 and src[i - 1] in "&^r" and (i < 2 or not (src[i - 2].isalnum() or src[i - 2] == "_")) else ""
            prefix = src[line_start:i]
            if src.startswith(q * 3, i):
                j = src.find(q * 3, i + 3)
                text = src[i + 3:j]
                yield line, _gd_unescape(text), prefix, marker
                line += text.count("\n")
                i = j + 3
                continue
            j = i + 1
            buf = []
            while j < n and src[j] != q:
                if src[j] == "\\" and j + 1 < n:
                    buf.append(src[j:j + 2])
                    j += 2
                    continue
                if src[j] == "\n":
                    break
                buf.append(src[j])
                j += 1
            text = "".join(buf)
            yield line, (text if marker == "r" else _gd_unescape(text)), prefix, marker
            i = j + 1
            continue
        i += 1


def code_files(folders=("scripts",)):
    for base in folders:
        for dirpath, _, files in os.walk(os.path.join(GODOT, base)):
            for f in sorted(files):
                if f.endswith(".gd"):
                    p = os.path.join(dirpath, f)
                    yield os.path.relpath(p, GODOT).replace(os.sep, "/"), open(p, encoding="utf-8").read()


LOG_CALL = re.compile(r"\b(print|prints|printt|printerr|print_rich|print_verbose|push_error|push_warning|assert|trace_load|_boot_mark|_log|log_line)\s*\(")
TR_CALL = re.compile(r"Lang\.t\(\s*$")
UI_FIELD = re.compile(r'"(name|desc|text|title|role|line|label|effect|hint|detail|short|subtitle|headline|caption|tip|note|message|prompt|unit)"\s*:\s*$')


def scan():
    """Every literal of godot/scripts with the reason it matters (tr / field / plain / log)."""
    found = []
    for rel, src in code_files():
        for line, text, prefix, marker in literals(src):
            if marker in ("&", "^"):
                continue
            kind = "plain"
            if LOG_CALL.search(prefix):
                kind = "log"
            elif TR_CALL.search(prefix):
                kind = "tr"
            elif UI_FIELD.search(prefix):
                kind = "field"
            found.append((rel, line, text, kind))
    return found

# ---------------------------------------------------------------- heuristics
PLACEHOLDER = re.compile(r"%(?:%|[-+0#]*\d*(?:\.\d+)?[scdoxXfv])")
UMLAUT = re.compile(r"[äöüÄÖÜß]")
WORD = re.compile(r"[A-Za-zÄÖÜäöüß]+")
IDENT = re.compile(r"^[a-z0-9_./:%=-]*$|^[A-Z0-9_]+$|^[^A-Za-zÄÖÜäöü]*$|^(res|user)://")


def placeholders(s):
    return [p for p in PLACEHOLDER.findall(s)]


def load_allow():
    allow = set()
    if os.path.exists(ALLOW):
        for raw in open(ALLOW, encoding="utf-8"):
            s = raw.rstrip("\n")
            if s and not s.startswith("#"):
                allow.add(_gd_unescape(s))
    return allow


def german_vocabulary(entries):
    """Words that only occur on the German side of the catalogue (plus a core list)."""
    en_words, de_words = set(), set()
    for k, v in entries.items():
        en_words.update(w.lower() for w in WORD.findall(k))
        de_words.update(w.lower() for w in WORD.findall(v))
    core = set("""und nicht ist mit für fuer auf einen einem einer zum zur bei vom nach über ueber unter
    alle alles nur noch schon jetzt wieder welle wellen spieler starten beenden zurück zurueck weiter
    einstellungen schwierigkeit steuerung bestenliste erfolge waffe waffen munition granate granaten leben
    punkte gekauft kaufen verkauft genug drücke druecke halte halten öffnen oeffnen schliessen hütte huette
    wald barrikade barrikaden turm türme tuerme reparieren gebaut bauen getötet kopfschuss runde nochmal
    fortsetzen keine kein kann wird werden wurde sind bist hast hat habe dich dein deine euch ihr wir uns
    unser auftrag aufträge schaden stufe gegner abschüsse verbindung wiederbeleben händler""".split())
    return ((de_words - en_words) | core) - {"vendor", "mechanic", "mods", "skins", "training", "normal", "r",
                                              "rem", "dollars", "mara", "hamachi", "lan", "udp", "ip", "fps"}


def has_words(text):
    """True when the text has letters outside its %d / %s placeholders."""
    return bool(re.search(r"[A-Za-zÄÖÜäöüß]{2,}", PLACEHOLDER.sub(" ", text)))


def looks_german(text, vocab):
    if UMLAUT.search(text):
        return True
    words = [w.lower() for w in WORD.findall(text)]
    return any(w in vocab for w in words if len(w) > 2)


def looks_english_ui(text):
    if IDENT.match(text) or len(text.strip()) < 2 or not has_words(text):
        return False
    letters = WORD.findall(text)
    if not letters:
        return False
    if " " in text.strip() or "\n" in text:
        return True
    return text[:1].isupper() and len(text) > 2

# ---------------------------------------------------------------- commands
def refs_of(entries, found):
    refs = {}
    for rel, line, text, kind in found:
        if text in entries:
            refs.setdefault(text, []).append((rel, line))
    return refs


def cmd_merge(paths):
    entries = read_po()
    conflicts = 0
    added = 0
    for p in paths:
        data = json.load(open(p, encoding="utf-8"))
        pairs = data.items() if isinstance(data, dict) else data
        for en, de in pairs:
            if not en or not isinstance(en, str) or not isinstance(de, str):
                continue
            if en in entries and entries[en] != de:
                conflicts += 1
                print(f"CONFLICT {os.path.basename(p)}: {en!r}\n   kept: {entries[en]!r}\n   new:  {de!r}")
                continue
            if en not in entries:
                added += 1
            entries[en] = de
    found = scan()
    write_po(entries, refs_of(entries, found))
    print(f"merged {added} new, {conflicts} conflicts, {len(entries)} total")


def cmd_write():
    entries = read_po()
    write_po(entries, refs_of(entries, scan()))
    print(f"rewrote {len(entries)} entries")


def _option(name):
    for arg in sys.argv:
        if arg.startswith(name + "="):
            return [x for x in arg.split("=", 1)[1].split(",") if x]
    return []


def _with_fragments(entries):
    """Catalogue plus not yet merged fragments (--with=a.json,b.json)."""
    for path in _option("--with"):
        data = json.load(open(path, encoding="utf-8"))
        for en, de in (data.items() if isinstance(data, dict) else data):
            entries.setdefault(en, de)
    return entries


def cmd_check(verbose=True):
    entries = _with_fragments(read_po())
    only = _option("--files")
    allow = load_allow()
    vocab = german_vocabulary(entries)
    found = scan()
    problems = 0
    used = set()
    for rel, line, text, kind in found:
        if text in entries:
            used.add(text)
        if kind == "log" or text in allow or (only and rel not in only):
            continue
        if kind in ("tr", "field") and has_words(text) and text not in entries and not IDENT.match(text):
            problems += 1
            print(f"MISSING  {rel}:{line}  {text!r}")
        elif looks_german(text, vocab) and text not in entries and not IDENT.match(text):
            problems += 1
            print(f"GERMAN   {rel}:{line}  {text!r}")
    for en, de in entries.items():
        if placeholders(en) != placeholders(de):
            problems += 1
            print(f"SLOTS    {en!r} -> {de!r}")
        if not de.strip():
            problems += 1
            print(f"EMPTY    {en!r}")
        other = entries.get(de)
        if de != en and other is not None and other != de:
            print(f"TWICE    {en!r} -> {de!r} -> {other!r}  (a label would translate it again)")
    unused = [en for en in entries if en not in used]
    if unused and verbose:
        print(f"note: {len(unused)} catalogue entries are not used as a literal (built at runtime or stale):")
        for en in unused[:40]:
            print(f"UNUSED   {en!r}")
    print(f"{len(entries)} entries, {problems} problems")
    return problems


def cmd_review():
    entries = _with_fragments(read_po())
    allow = load_allow()
    only = _option("--files")
    for rel, line, text, kind in scan():
        if kind == "log" or text in entries or text in allow or (only and rel not in only):
            continue
        if looks_english_ui(text):
            print(f"{rel}:{line}  [{kind}]  {text!r}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    cmd = sys.argv[1]
    if cmd == "merge":
        cmd_merge(sys.argv[2:])
    elif cmd == "write":
        cmd_write()
    elif cmd == "check":
        return 1 if cmd_check("--quiet" not in sys.argv) else 0
    elif cmd == "review":
        cmd_review()
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

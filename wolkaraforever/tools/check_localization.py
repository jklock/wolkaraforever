#!/usr/bin/env python3
"""Check the app's string tables against each other and against the source.

Three things are checked, and all three are the ways a table silently stops being a
translation:

1. Both tables have exactly the same keys.  A key in one and not the other is a row
   that falls back to English in one language and is untranslated in the other.
2. A key's conversions (``%@``, ``%lu``, ``%.0f%%`` ...) are the same in both.  A
   translation that drops or reorders a conversion crashes or prints ``(null)``.
3. Every key the source asks for exists in both tables.  This is what makes the
   runtime fallback ("never show a raw key") a belt-and-braces measure rather than
   the thing that saves the release.
4. No German string is simply the English one, unless it is one of the words that
   really is the same in both (a proper noun, "Name", "Region").  A translation that
   was never written is indistinguishable from a correct one at run time, so this is
   the only place it can be caught.

It also lists keys nothing asks for.  That is a notice, not a failure: plural forms
(``.one``/``.other``/``.zero``) and the base key they are looked up from are used
indirectly, so a strict reading would be wrong often enough to be ignored.

Run it from anywhere; it works on the repository root.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
TABLES = {
    "en": ROOT / "wolkaraforever/Shell/en.lproj/Localizable.strings",
    "de": ROOT / "wolkaraforever/Shell/de.lproj/Localizable.strings",
}
# Where product code lives.  platform/ is upstream's and is checked byte-for-byte by
# check_layers.sh; the tables are ours alone.
SOURCE_DIRS = ["wolkaraforever/Shell", "wolkaraforever/WoW", "wolkaraforever/Voice",
               "wolkaraforever/Touch", "wolkaraforever/Input", "wolkaraforever/Controller"]

CALL = re.compile(
    r'(?:WKLocalized|WKLocalizedFormat|WKLocalizedCount|WKLocalizedCountFormat'
    r'|AKHostLocalized|AKHostLocalizedFormat|AKHostLocalizedCount)\s*\(\s*@"([^"]+)"')
# A namespace a key is built from at run time: @"region." + value, or
# [@"locale." stringByAppendingString:...].  The keys under it are still ours to review, so
# they count as asked for rather than as dead weight.
PREFIX = re.compile(r'@"([a-z][a-z0-9]*\.)"\s*(?:\+|stringByAppendingString)')
# Any literal, so a key named in a table of its own (the About page's documents) counts as
# used even though it never reaches a call.
LITERAL = re.compile(r'@"([^"\n]+)"')
# A conversion, read by hand rather than by regex: the regex matched the second of a
# literal "%%" as the start of one, which is how "%.0f %% ausgelastet" was reported as
# carrying an "%a".
PLURAL_SUFFIXES = (".zero", ".one", ".other")
CONVERSION_CHARACTERS = set("@dDiuUxXoOfFeEgGcsSpaA")


def conversions(value):
    """The conversions in a format string, sorted, with the literal "%%" ignored."""
    found, index = [], 0
    while index < len(value):
        character = value[index]
        if character != "%":
            index += 1
            continue
        index += 1
        if index < len(value) and value[index] == "%":
            index += 1          # a literal per-cent, not an argument
            continue
        while index < len(value) and value[index] in "-+ #0*0123456789.":
            index += 1
        while index < len(value) and value[index] in "hlqjztL":
            index += 1
        if index < len(value) and value[index] in CONVERSION_CHARACTERS:
            found.append("%" + value[index])
        index += 1
    return sorted(found)


def has_key(table, key):
    """Whether a table can answer for a key, counting the plural forms it is looked up by."""
    if key in table:
        return True
    return any(key + suffix in table for suffix in PLURAL_SUFFIXES)


def parse_table(path):
    """Read a .strings file as key -> value, refusing anything ambiguous."""
    entries, keys = {}, []
    text = path.read_text(encoding="utf-8")
    # Strip comments first so a "//" inside a value cannot confuse the parser.
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'(?m)^\s*//.*$', '', text)
    for match in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text, re.S):
        key, value = match.group(1), match.group(2)
        if key in entries:
            raise SystemExit(f"{path}: {key} appears twice")
        entries[key] = value
        keys.append(key)
    return entries, keys


def conversions_of(value):
    return conversions(value)


def main():
    tables, order, failures, notices = {}, {}, [], []
    for code, path in TABLES.items():
        if not path.exists():
            failures.append(f"{path} does not exist")
            continue
        try:
            tables[code], order[code] = parse_table(path)
        except SystemExit as problem:
            failures.append(str(problem))
    if failures:
        for line in failures:
            print(f"FAIL {line}")
        print("check_localization: FAILED")
        return 1

    english, german = tables["en"], tables["de"]
    for key in order["en"]:
        if has_key(german, key):
            continue
        # A plural form one language does not need is not a gap: German writes "1 Add-on"
        # and "3 Add-ons" with the same words, so its table leaves ".one" out and the
        # "other" form is what both resolve to.
        if key.endswith(PLURAL_SUFFIXES) and has_key(german, key.rsplit(".", 1)[0]):
            continue
        failures.append(f"{key} is in en but not in de")
    for key in order["de"]:
        if not has_key(english, key):
            failures.append(f"{key} is in de but not in en")
    for key in order["en"]:
        if key not in german or not english[key]:
            continue
        if conversions(english[key]) != conversions(german[key]):
            failures.append(f"{key}: conversions differ: en {conversions(english[key])} "
                            f"de {conversions(german[key])}")
        if not german[key].strip():
            failures.append(f"{key}: the German string is empty")

    # Every key the source asks for, and where.
    used, literals, prefixes = {}, set(), set()
    for folder in SOURCE_DIRS:
        for path in sorted((ROOT / folder).rglob("*")):
            if path.suffix not in (".m", ".h", ".swift") or "/tests/" in str(path):
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                if line.lstrip().startswith("//") or line.lstrip().startswith("*"):
                    continue
                for key in CALL.findall(line):
                    used.setdefault(key, f"{path.relative_to(ROOT)}:{number}")
                literals.update(LITERAL.findall(line))
                prefixes.update(PREFIX.findall(line))
    for key, where in sorted(used.items()):
        if not has_key(english, key):
            failures.append(f"{where}: {key} is not in en.lproj")
        elif not has_key(german, key):
            failures.append(f"{where}: {key} is not in de.lproj")

    # Keys nothing asks for, ignoring plural forms whose base is used.
    def asked(key):
        if key in used or key in literals:
            return True
        if any(key.startswith(prefix) for prefix in prefixes):
            return True
        for suffix in PLURAL_SUFFIXES:
            if key.endswith(suffix) and key[:-len(suffix)] in used:
                return True
        return False
    unused = [key for key in order["en"] if not asked(key)]
    if unused:
        notices.append(f"{len(unused)} key(s) nothing asks for: {', '.join(unused[:8])}")
    # A German string identical to the English one is almost always a translation that was never
    # written. These are the ones that are the same word in both, each with why - adding one is a
    # decision, and a lazy translation is a failure.
    identical_is_fine = {
        "home.preferences.region": "Region is the German word",
        "region.kr": "proper noun",
        "region.tw": "proper noun",
        "addons.column.name": "Name is the German word",
        "addons.column.downloads": "Downloads is the German word",
        "addons.edition": "Edition is what Blizzard's German client calls it",
        "overlay.thermal.nominal": "the thermal state's name, and the same word",
        "overlay.thermal.fair.detail": "Warm is the German word",
        "touch.gamepad.button": "a German player says Controller too",
    }
    same = [key for key in order["en"] if key in german and english[key] == german[key]
            and re.search(r"[A-Za-z]{4,}", english[key])
            and not re.fullmatch(r"[^a-z]*", english[key])]
    for key in same:
        if key not in identical_is_fine:
            failures.append(f"{key}: the German string is the English one, and is not on the "
                            f"list of words that are the same in both")

    for line in notices:
        print(f"TODO {line}")
    for line in failures:
        print(f"FAIL {line}")
    print(f"check_localization: {len(english)} keys"
          f"{'' if not failures else ' - FAILED'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

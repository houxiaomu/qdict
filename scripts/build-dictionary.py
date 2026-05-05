#!/usr/bin/env python3
"""
Build QDict's bundled English dictionary from ECDICT CSV.

Usage:
    python3 scripts/build-dictionary.py /path/to/ecdict.csv \
        QDict/Dictionary/Resources/ecdict.sqlite

Source: https://github.com/skywind3000/ECDICT — use the "ECDICT" or
"ECDICT_FREE" CSV release. License is MIT.

Filter rules (see spec §5.1):
    keep if (frq <= 15000) OR (collins >= 1) OR (oxford == 1)
    exclude if word starts with capital letter (proper nouns)
    exclude if word contains '_'
    exclude if translation empty
"""
import csv
import os
import sqlite3
import sys


GLOSS_MAX = 80

# A part-of-speech token at the head of a translation looks like one of these,
# always followed by a space. ECDICT uses both "a." and "adj.", "n." and "noun"
# is rare. Listing the long forms first matters because we're prefix-matching.
POS_TOKENS = (
    "adj.", "adv.", "prep.", "conj.", "pron.", "num.", "art.", "interj.",
    "aux.", "abbr.",
    "vt.", "vi.", "vd.",
    "n.", "v.", "a.", "i.",
)


def normalize_gloss(raw: str) -> str:
    """Collapse multi-line ECDICT translations onto one line.

    ECDICT stores newlines as the literal two-character sequence ``\\n``
    rather than a real newline, plus occasional real newlines if the export
    differs. Handle both, and clamp to ``GLOSS_MAX`` characters.
    """
    g = raw.replace("\r", "").replace("\\n", "；").replace("\n", "；").strip()
    # Collapse runs of separators created when the body started with a newline.
    while "；；" in g:
        g = g.replace("；；", "；")
    g = g.strip("； ").strip()
    if len(g) > GLOSS_MAX:
        g = g[: GLOSS_MAX - 1] + "…"
    return g


def split_pos_and_gloss(translation_normalized: str):
    """Pull a leading POS token off the front of the gloss.

    ECDICT only fills the dedicated ``pos`` column for a small minority of
    rows; for everyone else, the part-of-speech is the first token of the
    translation, e.g. ``"n. 苹果, 家伙"``. Splitting it lets the UI render
    it in italics separate from the gloss body, matching the mockup.
    """
    s = translation_normalized
    for tok in POS_TOKENS:
        if s.startswith(tok + " "):
            return tok, s[len(tok) + 1 :].lstrip()
    return None, s


def normalize_pos(raw: str):
    p = (raw or "").strip()
    return p if p else None


def parse_int(raw: str):
    """ECDICT uses 0 to mean "no rank / not in this corpus" rather than
    "ranked at position zero". Treat empty and 0 the same — both as None —
    so downstream filtering and sorting do the right thing.
    """
    s = (raw or "").strip()
    if not s:
        return None
    try:
        v = int(s)
    except ValueError:
        return None
    return v if v > 0 else None


def should_keep(word: str, translation: str, frq, collins, oxford) -> bool:
    """Filter rules.

    Quality signals are: frq (COCA rank ≤ 15000), collins (any star), or
    oxford (== 1). At least one must be present. The corpus normalizes
    ``frq=0``/``collins=''`` to ``None`` upstream.

    Capitalized words are accepted *only when they carry a quality signal* —
    that admits curated entries like "Epiphany" (the holiday) while still
    rejecting the long tail of personal/place names that have no rank.
    Skipping the capital filter entirely would drag in tens of thousands of
    proper nouns like ``Epipactis`` (a plant genus) which the user is very
    unlikely to be searching for in a translator panel.
    """
    if not word or not translation:
        return False
    if "_" in word:
        return False
    has_signal = (
        (frq is not None and frq <= 15000)
        or (collins is not None and collins >= 1)
        or (oxford == 1)
    )
    if not has_signal:
        return False
    return True


def build(csv_path: str, sqlite_path: str) -> None:
    if os.path.exists(sqlite_path):
        os.remove(sqlite_path)
    parent = os.path.dirname(sqlite_path)
    if parent:
        os.makedirs(parent, exist_ok=True)

    conn = sqlite3.connect(sqlite_path)
    conn.execute("PRAGMA journal_mode = OFF")
    conn.execute("PRAGMA synchronous = OFF")
    conn.execute(
        """
        CREATE TABLE entries (
            word    TEXT NOT NULL PRIMARY KEY,
            display TEXT NOT NULL,
            pos     TEXT,
            gloss   TEXT NOT NULL,
            coca    INTEGER,
            collins INTEGER
        )
        """
    )

    kept = 0
    skipped = 0
    seen_lower = set()
    with open(csv_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = (row.get("word") or "").strip()
            translation = (row.get("translation") or "").strip()
            frq = parse_int(row.get("frq", ""))
            collins = parse_int(row.get("collins", ""))
            oxford = parse_int(row.get("oxford", ""))
            if not should_keep(word, translation, frq, collins, oxford):
                skipped += 1
                continue
            lower = word.lower()
            if lower in seen_lower:
                skipped += 1
                continue
            seen_lower.add(lower)
            gloss = normalize_gloss(translation)
            pos = normalize_pos(row.get("pos", ""))
            if pos is None:
                pos, gloss = split_pos_and_gloss(gloss)
            conn.execute(
                "INSERT INTO entries (word, display, pos, gloss, coca, collins) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (
                    lower,
                    word,
                    pos,
                    gloss,
                    frq,
                    collins,
                ),
            )
            kept += 1
    conn.commit()
    conn.execute("VACUUM")
    conn.close()

    size_mb = os.path.getsize(sqlite_path) / (1024 * 1024)
    print(
        f"Kept {kept} entries (skipped {skipped}). "
        f"Output: {sqlite_path} ({size_mb:.2f} MB)"
    )


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    build(sys.argv[1], sys.argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main())

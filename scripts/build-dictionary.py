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


def normalize_gloss(raw: str) -> str:
    g = raw.replace("\r", "").replace("\n", "；").strip()
    if len(g) > GLOSS_MAX:
        g = g[: GLOSS_MAX - 1] + "…"
    return g


def normalize_pos(raw: str):
    p = (raw or "").strip()
    return p if p else None


def parse_int(raw: str):
    s = (raw or "").strip()
    if not s:
        return None
    try:
        return int(s)
    except ValueError:
        return None


def should_keep(word: str, translation: str, frq, collins, oxford) -> bool:
    if not word or not translation:
        return False
    if word[0].isupper():
        return False
    if "_" in word:
        return False
    if frq is not None and frq <= 15000:
        return True
    if collins is not None and collins >= 1:
        return True
    if oxford == 1:
        return True
    return False


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
            conn.execute(
                "INSERT INTO entries (word, display, pos, gloss, coca, collins) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (
                    lower,
                    word,
                    normalize_pos(row.get("pos", "")),
                    normalize_gloss(translation),
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

# Dictionary build

QDict ships an offline English dictionary at
`shared/dictionary/ecdict.sqlite`. It is generated from
[ECDICT](https://github.com/skywind3000/ECDICT) (MIT) by
`scripts/build-dictionary.py`.

## Regenerate

1. Download ECDICT CSV (e.g. `ecdict.csv` from the project's GitHub releases).
2. From the repo root:

   ```bash
   python3 scripts/build-dictionary.py /path/to/ecdict.csv \
       shared/dictionary/ecdict.sqlite
   ```

3. Commit the regenerated `ecdict.sqlite` alongside any related changes.

## Filter rules

See spec §5.1 in `docs/superpowers/specs/2026-05-05-input-suggestion-design.md`.

# foliate-sync — v0.1.0

Syncs your Foliate library with books on disk. Running without flags shows a
preview of what would change — use `--run` to apply.

Available in **English**, **Spanish**, and **Portuguese**.
Language is auto-detected from `$LANG`; override with `--lang`.

See [DEPS.md](DEPS.md) for installation instructions per distro.

---

## Usage

```bash
chmod +x foliate-sync.sh

./foliate-sync.sh                              # preview: show config + counts
./foliate-sync.sh --run                        # sync: add new books, prompt for removed ones
./foliate-sync.sh --run --dry-run              # simulate sync without modifying anything
./foliate-sync.sh --run --quiet                # sync with summary only
./foliate-sync.sh --run --no-covers            # sync without generating covers
./foliate-sync.sh --books-dir ~/Downloads      # override books folder (preview)
./foliate-sync.sh --books-dir ~/Downloads --run  # override books folder + sync
./foliate-sync.sh --lang es                    # force Spanish output
./foliate-sync.sh --lang pt                    # force Portuguese output
./foliate-sync.sh --clean                      # clear catalog (asks confirmation)
./foliate-sync.sh --clean -y                   # clear catalog without confirmation
```

Restart Foliate after running to see the changes.

---

## Default behavior

Running `./foliate-sync.sh` without `--run` shows a preview:

```
Books folder:        /home/user/Books
Extensions:          epub pdf mobi azw azw3 cbz cbr
Covers enabled:      256 px

Preview:
  Books on disk:             45
  Already in library:        43
  New to add:                 2
  Missing from disk:          1  (will prompt for removal)

Run with --run to sync.
```

---

## Configuration — `config.toml`

```toml
# Root folder with books (supports ~)
books_dir = "~/Books"

# Formats to import (remove any you don't want)
extensions = ["epub", "pdf", "mobi", "azw", "azw3", "cbz", "cbr"]

# Cover width in pixels (height is proportional)
cover_width = 256
```

The `--books-dir` flag overrides `books_dir` from the config at runtime.

---

## Sync behavior

On each `--run`, the script:

1. **Adds** books found on disk that are not yet in the Foliate library.
2. **Detects** library entries whose files no longer exist on disk and prompts
   per book: `Remove from library? [y/N]`. Reading progress is never touched
   automatically — only removed when you explicitly confirm deletion.

---

## Files written

| Purpose         | Path                                                                        |
|-----------------|-----------------------------------------------------------------------------|
| Config          | `<script-dir>/config.toml`                                                  |
| Catalog         | `~/.local/share/com.github.johnfactotum.Foliate/library/uri-store.json`     |
| Book metadata   | `~/.local/share/com.github.johnfactotum.Foliate/{id}.json`                  |
| Cover cache     | `~/.cache/com.github.johnfactotum.Foliate/{id}.png`                         |

---

## How it works

For each new book the script does three things:

1. **Catalog** — appends `[id, path]` to `uri-store.json` if not already present.

2. **Metadata** — creates `{id}.json` with title, author, language, publisher.
   This file is **required**: without it Foliate ignores the catalog entry.
   Existing `{id}.json` files are never overwritten (reading progress is preserved).

3. **Cover** — generates `{id}.png` (width = `cover_width`) in the cache dir.
   Without it, Foliate shows a placeholder until the book is opened manually.

   | Format | Source |
   |--------|--------|
   | EPUB   | Embedded cover image from the OPF manifest, resized with `magick` |
   | PDF    | First page rendered with `pdftoppm` |
   | CBZ    | First image in the ZIP archive, resized with `magick` |

Identifiers are computed as:

- **EPUB** — `dc:identifier` UUID from the OPF (`unique-identifier` attribute)
- **PDF / MOBI / AZW / CBZ / CBR** — `foliate:{md5}` of the file content

---

## Clean

```bash
./foliate-sync.sh --clean      # shows what will be deleted + progress warning, asks confirmation
./foliate-sync.sh --clean -y   # deletes without asking
```

Deletes: `uri-store.json` (reset to empty), all `{id}.json` metadata files
(including reading progress), all `{id}.png` cover files.

---

## Example output (`--run`)

```
Books folder:        /home/user/Books
Extensions:          epub pdf mobi azw azw3 cbz cbr
Covers enabled:      256 px

[ 1/30] ✓ Literature/Borges/Ficciones.epub
         title:    Ficciones
         id:       urn:uuid:4a1b2c3d-...
         cover:    generated
[ 2/30] → Science/Newton - Principia.epub
[ 3/30] → Science/Euler.pdf  [cover generated]
[ 4/30] ✗ Corrupted/bad.epub  (corrupt file: bad ZIP/EPUB)

Books in library whose files no longer exist:

  ~/Books/OldNovel.epub  (title: Deleted Book)
  Remove from library? [y/N] y
  ✓ removed from library

────────────────────────────────────────────────────────
Total books              30
Added                     1
Covers generated          2
Already imported         28
Removed from library      1
Corrupt                   1
```

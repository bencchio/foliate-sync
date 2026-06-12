# Dependencies

## Required

| Tool         | Purpose                              |
|--------------|--------------------------------------|
| `foliate`    | The e-book reader itself             |
| `python3`    | Book identifiers and metadata        |
| `magick`     | Cover conversion (EPUB, CBZ)         |
| `pdftoppm`   | Cover rendering (PDF)                |

`python3` uses only the standard library — no pip packages needed.

---

## Arch Linux

```bash
sudo pacman -S foliate python imagemagick poppler
```

---

## Fedora

```bash
sudo dnf install foliate python3 ImageMagick poppler-utils
```

> Foliate may not be in the default repos on older Fedora releases.
> Install via Flatpak as a fallback:
> ```bash
> flatpak install flathub com.github.johnfactotum.Foliate
> ```

---

## Ubuntu / Debian

```bash
sudo apt install foliate python3 imagemagick poppler-utils
```

> On Ubuntu 22.04 or earlier, `foliate` may be outdated in the repos.
> Install via Flatpak as a fallback:
> ```bash
> flatpak install flathub com.github.johnfactotum.Foliate
> ```

---

## Notes

- `magick` and `pdftoppm` are **optional** — the script warns if they are
  missing and skips cover generation for the affected formats.
- If Foliate is installed via Flatpak, the data paths remain the same:
  `~/.local/share/com.github.johnfactotum.Foliate/`

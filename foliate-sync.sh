#!/usr/bin/env bash
# foliate-sync.sh — Sync Foliate library with books on disk.
# Default: show preview. Use --run to apply changes.
# Version: 0.1.0

VERSION="0.1.0"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.toml"
FOLIATE_DATA="$HOME/.local/share/com.github.johnfactotum.Foliate"
FOLIATE_CACHE="$HOME/.cache/com.github.johnfactotum.Foliate"
LIBRARY_FILE="$FOLIATE_DATA/library/uri-store.json"

tildify() { echo "${1/#$HOME/\~}"; }

# ─── Colors ───────────────────────────────────────────────────────────────────

if [[ -t 1 && "${NO_COLOR:-}" == "" ]]; then
    C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'
    C_CYAN='\033[0;36m';  C_BOLD='\033[1m';       C_DIM='\033[2m'
    C_RESET='\033[0m'
else
    C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RESET=''
fi

# ─── i18n ─────────────────────────────────────────────────────────────────────

_LANG_CODE=""
_BOOKS_DIR_ARG=""
_prev=""
for _a in "$@"; do
    [[ "$_prev" == "--lang" ]]      && _LANG_CODE="$_a"
    [[ "$_prev" == "--books-dir" ]] && _BOOKS_DIR_ARG="$_a"
    case "$_a" in
        --lang=*)      _LANG_CODE="${_a#--lang=}" ;;
        --books-dir=*) _BOOKS_DIR_ARG="${_a#--books-dir=}" ;;
    esac
    _prev="$_a"
done

if [[ -z "$_LANG_CODE" ]]; then
    case "${LANG:-en}" in
        es*) _LANG_CODE="es" ;;
        pt*) _LANG_CODE="pt" ;;
        *)   _LANG_CODE="en" ;;
    esac
fi

init_lang() {
    local lang_file="$SCRIPT_DIR/locale/${_LANG_CODE}.sh"
    if [[ ! -f "$lang_file" ]]; then
        local avail
        avail=$(ls "$SCRIPT_DIR/locale/"*.sh 2>/dev/null \
                | xargs -I{} basename {} .sh | sort | tr '\n' '|' | sed 's/|$//')
        echo "Error: invalid language '${_LANG_CODE}'. Available: ${avail:-en|es|pt}." >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$lang_file"
}

init_lang

# ─── Help ─────────────────────────────────────────────────────────────────────

show_help() {
    printf "${C_BOLD}foliate-sync${C_RESET}  —  %s\n" "$L_DESC"
    printf "%s\n\n" "$L_DESC2"
    printf "${C_BOLD}%s${C_RESET}\n" "$L_OPT_HDR"
    printf "%s\n" "$L_OPT_HELP"
    printf "%s\n" "$L_OPT_RUN"
    printf "%s\n" "$L_OPT_LANG"
    printf "%s\n" "$L_OPT_BDIR"
    printf "%s\n" "$L_OPT_DRY"
    printf "%s\n" "$L_OPT_NO_COV"
    printf "%s\n" "$L_OPT_QUIET"
    printf "%s\n\n" "$L_OPT_CLEAN"
    printf "${C_BOLD}%s${C_RESET}\n" "$L_CFG_HDR"
    printf "%s\n" "$L_CFG_BDIR"
    printf "%s\n" "$L_CFG_EXT"
    printf "%s\n\n" "$L_CFG_WIDTH"
    printf "${C_BOLD}%s${C_RESET}\n" "$L_FILES_HDR"
    printf "  %s\n" "~/.local/share/com.github.johnfactotum.Foliate/library/uri-store.json"
    printf "  %s\n" "~/.local/share/com.github.johnfactotum.Foliate/{id}.json"
    printf "  %s\n\n" "~/.cache/com.github.johnfactotum.Foliate/{id}.png"
    printf "${C_DIM}%s${C_RESET}\n" "$L_NOTE"
}

# ─── Arguments ────────────────────────────────────────────────────────────────

DRY_RUN=false
GEN_COVERS=true
CLEAN=false
YES=false
QUIET=false
RUN=false

_skip_next=false
for arg in "$@"; do
    if [[ "$_skip_next" == true ]]; then _skip_next=false; continue; fi
    case "$arg" in
        -h|--help)       show_help; exit 0 ;;
        --version)       echo "foliate-sync $VERSION"; exit 0 ;;
        --lang)          _skip_next=true ;;
        --lang=*)        : ;;
        --books-dir)     _skip_next=true ;;
        --books-dir=*)   : ;;
        --run)           RUN=true ;;
        --dry-run)       DRY_RUN=true; RUN=true ;;
        --no-covers)     GEN_COVERS=false ;;
        --quiet)         QUIET=true ;;
        --clean)         CLEAN=true ;;
        -y|--yes)        YES=true ;;
        *)
            echo "${C_RED}Error: unknown option '$arg'${C_RESET}" >&2
            show_help; exit 1
            ;;
    esac
done

# ─── Config ───────────────────────────────────────────────────────────────────

[[ -f "$CONFIG_FILE" ]] || { echo "$L_ERR_CFG $SCRIPT_DIR" >&2; exit 1; }

BOOKS_DIR=$(grep -E '^books_dir\s*=' "$CONFIG_FILE" | sed 's/.*=\s*"\(.*\)"/\1/' | head -1 || true)
BOOKS_DIR="${BOOKS_DIR/#\~/$HOME}"
[[ -n "$BOOKS_DIR" ]] || { echo "$L_ERR_BDIR" >&2; exit 1; }

# --books-dir takes precedence over config.toml
[[ -n "$_BOOKS_DIR_ARG" ]] && BOOKS_DIR="${_BOOKS_DIR_ARG/#\~/$HOME}"

BOOKS_DIR_MISSING=false
[[ -d "$BOOKS_DIR" ]] || BOOKS_DIR_MISSING=true

EXTENSIONS_LINE=$(grep -E '^extensions\s*=' "$CONFIG_FILE" | sed 's/.*=\s*\[//' | sed 's/\]//' | head -1 || true)
if [[ -n "$EXTENSIONS_LINE" ]]; then
    mapfile -t EXTENSIONS < <(echo "$EXTENSIONS_LINE" | tr ',' '\n' | sed 's/[" ]//g' | grep -v '^$')
else
    EXTENSIONS=("epub" "pdf" "mobi" "azw" "azw3" "cbz" "cbr")
fi

COVER_WIDTH=$(grep -E '^cover_width\s*=' "$CONFIG_FILE" | sed 's/.*=\s*//' | tr -d ' ' | head -1 || true)
COVER_WIDTH="${COVER_WIDTH:-256}"
[[ "$COVER_WIDTH" =~ ^[0-9]+$ ]] || COVER_WIDTH=256

# ─── Clean ────────────────────────────────────────────────────────────────────

do_clean() {
    local meta_files=() cover_files=()
    mapfile -t meta_files  < <(find "$FOLIATE_DATA"  -maxdepth 1 -name '*.json' 2>/dev/null | sort)
    mapfile -t cover_files < <(find "$FOLIATE_CACHE" -maxdepth 1 -name '*.png'  2>/dev/null | sort)

    printf "${C_BOLD}%s${C_RESET}\n" "$L_CLEAN_HDR"
    printf "  %-12s: %s  →  {\"uris\":[]}\n" "$L_CLEAN_CAT" "$(tildify "$LIBRARY_FILE")"
    printf "  %-12s: %d %s %s/\n" "$L_CLEAN_META" "${#meta_files[@]}"  "$L_CLEAN_FILES" "$(tildify "$FOLIATE_DATA")"
    printf "  %-12s: %d %s %s/\n" "$L_CLEAN_COV"  "${#cover_files[@]}" "$L_CLEAN_FILES" "$(tildify "$FOLIATE_CACHE")"
    echo ""
    printf "${C_YELLOW}${C_BOLD}⚠  %s${C_RESET}\n" "$L_CLEAN_WARN"
    echo ""

    if [[ "$YES" == false ]]; then
        read -r -p "$L_CLEAN_CONFIRM" resp
        [[ "${resp,,}" == "$L_CLEAN_YES" ]] || { echo "$L_CLEAN_CANCEL"; exit 0; }
    fi

    mkdir -p "$(dirname "$LIBRARY_FILE")"
    echo '{"uris":[]}' > "$LIBRARY_FILE"
    [[ ${#meta_files[@]}  -gt 0 ]] && rm -f "${meta_files[@]}"
    [[ ${#cover_files[@]} -gt 0 ]] && rm -f "${cover_files[@]}"

    echo ""
    printf "${C_GREEN}✓ %s${C_RESET}\n" "$L_CLEAN_DONE"
    echo ""
    printf "  %-16s %s\n" "${L_PATH_CAT}:"  "$(tildify "$LIBRARY_FILE")"
    printf "  %-16s %s/{id}.json\n" "${L_PATH_META}:" "$(tildify "$FOLIATE_DATA")"
    printf "  %-16s %s/{id}.png\n"  "${L_PATH_COV}:"  "$(tildify "$FOLIATE_CACHE")"
    echo ""
    printf "${C_DIM}%s${C_RESET}\n" "$L_NOTE"
}

if [[ "$BOOKS_DIR_MISSING" == true && "$RUN" == true ]]; then
    echo "${C_RED}${L_ERR_DIR} $BOOKS_DIR${C_RESET}" >&2
    exit 1
fi

[[ "$CLEAN" == true ]] && { do_clean; exit 0; }

# ─── Preview (default, no --run) ──────────────────────────────────────────────

show_preview() {
    if [[ "$BOOKS_DIR_MISSING" == true ]]; then
        printf "${C_BOLD}%-20s${C_RESET} ${C_YELLOW}%s${C_RESET}  ${C_DIM}(%s)${C_RESET}\n" \
               "${L_HDR_BDIR}:" "$BOOKS_DIR" "$L_WARN_DIR"
    else
        printf "${C_BOLD}%-20s${C_RESET} %s\n" "${L_HDR_BDIR}:" "$BOOKS_DIR"
    fi
    printf "${C_BOLD}%-20s${C_RESET} %s\n" "${L_HDR_EXT}:"  "${EXTENSIONS[*]}"
    [[ "$GEN_COVERS" == true  ]] && printf "${C_BOLD}%-20s${C_RESET} %s px\n" "${L_HDR_COV_ON}:" "$COVER_WIDTH"
    [[ "$GEN_COVERS" == false ]] && printf "${C_BOLD}%-20s${C_RESET}\n" "${L_HDR_COV_OFF}"
    echo ""

    if [[ "$BOOKS_DIR_MISSING" == true ]]; then
        printf "${C_BOLD}%s${C_RESET}\n" "$L_PATHS_HDR"
        printf "  %-16s %s\n" "${L_PATH_CFG}:" "$(tildify "$CONFIG_FILE")"
        echo ""
        return
    fi

    local result
    result=$(python3 - "$BOOKS_DIR" "$LIBRARY_FILE" "${EXTENSIONS[*]}" 2>/dev/null <<'PYEOF'
import sys, os, json

books_dir = sys.argv[1]
lib_file  = sys.argv[2]
exts      = set(sys.argv[3].split())
home      = os.path.expanduser('~')

disk_files = set()
for root, dirs, files in os.walk(books_dir):
    dirs.sort()
    for fname in sorted(files):
        ext = os.path.splitext(fname)[1].lower().lstrip('.')
        if ext in exts:
            disk_files.add(os.path.join(root, fname))

try:
    with open(lib_file) as f:
        data = json.load(f)
    lib_entries = data.get('uris', [])
except Exception:
    lib_entries = []

lib_paths = set()
for entry in lib_entries:
    if len(entry) >= 2:
        p = entry[1]
        if p.startswith('~'):
            p = home + p[1:]
        lib_paths.add(p)

already    = len(disk_files & lib_paths)
new_to_add = len(disk_files - lib_paths)
missing    = len(lib_paths - disk_files)

print(f"{len(disk_files)}\t{already}\t{new_to_add}\t{missing}")
PYEOF
    ) || result="0\t0\t0\t0"

    IFS=$'\t' read -r n_disk n_already n_new n_missing <<< "$result"

    printf "${C_BOLD}%s${C_RESET}\n" "$L_PREVIEW_HDR"
    printf "  ${C_BOLD}%-28s${C_RESET} %d\n" "${L_PREVIEW_DISK}:"    "$n_disk"
    printf "  %-28s %d\n"                     "${L_PREVIEW_ALREADY}:" "$n_already"
    printf "  ${C_GREEN}%-28s${C_RESET} %d\n" "${L_PREVIEW_NEW}:"     "$n_new"
    if [[ "$n_missing" -gt 0 ]]; then
        printf "  ${C_YELLOW}%-28s${C_RESET} %d  ${C_DIM}(%s)${C_RESET}\n" \
               "${L_PREVIEW_MISSING}:" "$n_missing" "$L_PREVIEW_MISSING_NOTE"
    else
        printf "  %-28s %d\n" "${L_PREVIEW_MISSING}:" "$n_missing"
    fi
    echo ""
    printf "${C_DIM}%s${C_RESET}\n" "$L_PREVIEW_HINT"
    echo ""
    printf "${C_BOLD}%s${C_RESET}\n" "$L_PATHS_HDR"
    printf "  %-16s %s\n" "${L_PATH_CFG}:"  "$(tildify "$CONFIG_FILE")"
    printf "  %-16s %s\n" "${L_PATH_CAT}:"  "$(tildify "$LIBRARY_FILE")"
    printf "  %-16s %s/{id}.json\n" "${L_PATH_META}:" "$(tildify "$FOLIATE_DATA")"
    printf "  %-16s %s/{id}.png\n"  "${L_PATH_COV}:"  "$(tildify "$FOLIATE_CACHE")"
    echo ""
}

if [[ "$RUN" == false ]]; then
    show_preview
    exit 0
fi

# ─── Dependencies (only needed for --run) ─────────────────────────────────────

command -v python3 &>/dev/null || { echo "$L_ERR_PYTHON" >&2; exit 1; }

HAS_MAGICK=false; HAS_PDFTOPPM=false
if [[ "$GEN_COVERS" == true ]]; then
    command -v magick    &>/dev/null && HAS_MAGICK=true    || echo "${C_YELLOW}${L_WARN_MAGICK}${C_RESET}" >&2
    command -v pdftoppm &>/dev/null && HAS_PDFTOPPM=true   || echo "${C_YELLOW}${L_WARN_PDFTOPPM}${C_RESET}" >&2
fi

# ─── Init library ─────────────────────────────────────────────────────────────

if [[ ! -f "$LIBRARY_FILE" && "$DRY_RUN" == false ]]; then
    mkdir -p "$(dirname "$LIBRARY_FILE")"
    echo '{"uris":[]}' > "$LIBRARY_FILE"
fi

# ─── import_book ──────────────────────────────────────────────────────────────

# Returns TSV: {lib_status}\t{cover_status}\t{id}\t{title}
#   lib_status  : ADD | SKIP | CORRUPT | ERROR
#   cover_status: ok | cached | no-cover | no-tool | error | skipped
import_book() {
    local file="$1"
    python3 - "$file" "$LIBRARY_FILE" "$FOLIATE_DATA" "$FOLIATE_CACHE" \
              "$DRY_RUN" "$GEN_COVERS" "$HAS_MAGICK" "$HAS_PDFTOPPM" "$COVER_WIDTH" <<'PYEOF'
import json, sys, os, zipfile, re, hashlib, urllib.parse, subprocess, tempfile, glob, shutil

filepath, lib_file, data_dir, cache_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
dry_run      = sys.argv[5] == "true"
gen_covers   = sys.argv[6] == "true"
has_magick   = sys.argv[7] == "true"
has_pdftoppm = sys.argv[8] == "true"
cover_width  = sys.argv[9]
home         = os.path.expanduser("~")

def check_integrity(path, ext):
    try:
        if os.path.getsize(path) == 0:
            return False, "empty file"
        if ext == 'epub':
            with zipfile.ZipFile(path) as z:
                if not any(n.lower().endswith('.opf') for n in z.namelist()):
                    return False, "no OPF found"
        elif ext == 'pdf':
            with open(path, 'rb') as f:
                if f.read(5) != b'%PDF-':
                    return False, "invalid PDF header"
        return True, None
    except zipfile.BadZipFile:
        return False, "bad ZIP/EPUB"
    except Exception as e:
        return False, str(e)[:60]

def md5_id(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(65536), b''):
            h.update(chunk)
    return 'foliate:' + h.hexdigest()

def get_epub_info(path):
    try:
        with zipfile.ZipFile(path) as z:
            opf_name = next((n for n in z.namelist() if n.lower().endswith('.opf')), None)
            if not opf_name:
                raise ValueError("no OPF")
            content = z.read(opf_name).decode('utf-8', errors='replace')
    except Exception:
        return md5_id(path), None, None, None, None

    def tag(name):
        m = re.search(rf'<dc:{name}[^>]*>([^<]+)</dc:{name}>', content)
        return m.group(1).strip() if m else None

    def tags(name):
        found = [m.strip() for m in re.findall(rf'<dc:{name}[^>]*>([^<]+)</dc:{name}>', content)]
        return found or None

    uid_attr = re.search(r'unique-identifier=["\']([^"\']+)["\']', content)
    identifier = None
    if uid_attr:
        m = re.search(
            rf'<dc:identifier[^>]+id=["\']' + re.escape(uid_attr.group(1)) + r'["\'][^>]*>([^<]+)</dc:identifier>',
            content)
        if m:
            identifier = m.group(1).strip()
    if not identifier:
        m = re.search(r'<dc:identifier[^>]*>([^<]+)</dc:identifier>', content)
        if m:
            identifier = m.group(1).strip()
    if not identifier:
        identifier = md5_id(path)

    return identifier, tag('title'), tags('creator'), tag('language'), tag('publisher')

def find_epub_cover_data(path):
    try:
        with zipfile.ZipFile(path) as z:
            opf_name = next((n for n in z.namelist() if n.lower().endswith('.opf')), None)
            if not opf_name:
                return None, None
            content = z.read(opf_name).decode('utf-8', errors='replace')
            opf_dir = os.path.dirname(opf_name)
            cover_href = None

            for pat in [
                r'<item\b[^>]+\bproperties=["\'][^"\']*\bcover-image\b[^"\']*["\'][^>]+\bhref=["\']([^"\']+)["\']',
                r'<item\b[^>]+\bhref=["\']([^"\']+)["\'][^>]+\bproperties=["\'][^"\']*\bcover-image\b[^"\']*["\']',
            ]:
                m = re.search(pat, content)
                if m:
                    cover_href = m.group(1)
                    break

            if not cover_href:
                for pat in [
                    r'<meta\b[^>]+\bname=["\']cover["\'][^>]+\bcontent=["\']([^"\']+)["\']',
                    r'<meta\b[^>]+\bcontent=["\']([^"\']+)["\'][^>]+\bname=["\']cover["\']',
                ]:
                    m = re.search(pat, content)
                    if m:
                        cid = m.group(1).strip()
                        for p2 in [
                            rf'<item\b[^>]+\bid=["\']' + re.escape(cid) + r'["\'][^>]+\bhref=["\']([^"\']+)["\']',
                            rf'<item\b[^>]+\bhref=["\']([^"\']+)["\'][^>]+\bid=["\']' + re.escape(cid) + r'["\']',
                        ]:
                            m2 = re.search(p2, content)
                            if m2:
                                cover_href = m2.group(1)
                                break
                        if cover_href:
                            break

            if not cover_href:
                for cid in ['cover-image', 'cover']:
                    for pat in [
                        rf'<item\b[^>]+\bid=["\']' + re.escape(cid) + r'["\'][^>]+\bhref=["\']([^"\']+)["\']',
                        rf'<item\b[^>]+\bhref=["\']([^"\']+)["\'][^>]+\bid=["\']' + re.escape(cid) + r'["\']',
                    ]:
                        m = re.search(pat, content)
                        if m:
                            cover_href = m.group(1)
                            break
                    if cover_href:
                        break

            if not cover_href:
                return None, None

            from urllib.parse import unquote
            href   = unquote(cover_href.split('?')[0].split('#')[0])
            in_zip = os.path.normpath((opf_dir + '/' + href) if opf_dir else href)
            actual = {n.lower(): n for n in z.namelist()}.get(in_zip.lower())
            if not actual:
                return None, None
            return z.read(actual), os.path.splitext(actual)[1] or '.jpg'
    except Exception:
        return None, None

def run_magick(src, out):
    r = subprocess.run(['magick', src, '-resize', f'{cover_width}x', out],
                       capture_output=True, timeout=30)
    return 'ok' if r.returncode == 0 else 'error'

def generate_epub_cover(path, out):
    if not has_magick:
        return 'no-tool'
    img_data, img_ext = find_epub_cover_data(path)
    if img_data is None:
        return 'no-cover'
    with tempfile.NamedTemporaryFile(suffix=img_ext, delete=False) as tmp:
        tmp.write(img_data); tmp_path = tmp.name
    try:
        return run_magick(tmp_path, out)
    except Exception:
        return 'error'
    finally:
        try: os.unlink(tmp_path)
        except Exception: pass

def generate_pdf_cover(path, out):
    if not has_pdftoppm:
        return 'no-tool'
    try:
        with tempfile.TemporaryDirectory() as tmp:
            prefix = os.path.join(tmp, 'p')
            r = subprocess.run(
                ['pdftoppm', '-png', '-f', '1', '-l', '1',
                 '-scale-to-x', cover_width, '-scale-to-y', '-1', path, prefix],
                capture_output=True, timeout=60)
            pages = sorted(glob.glob(f'{prefix}*.png'))
            if pages:
                shutil.copy(pages[0], out)
                return 'ok'
        return 'error'
    except Exception:
        return 'error'

def generate_cbz_cover(path, out):
    if not has_magick:
        return 'no-tool'
    try:
        with zipfile.ZipFile(path) as z:
            imgs = sorted(n for n in z.namelist()
                          if n.lower().endswith(('.jpg', '.jpeg', '.png', '.webp')))
            if not imgs:
                return 'no-cover'
            data = z.read(imgs[0])
            ext  = os.path.splitext(imgs[0])[1] or '.jpg'
        with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
            tmp.write(data); tmp_path = tmp.name
        try:
            return run_magick(tmp_path, out)
        finally:
            try: os.unlink(tmp_path)
            except Exception: pass
    except Exception:
        return 'error'

def make_cover(path, ext, book_id):
    if not gen_covers or dry_run:
        return 'skipped'
    os.makedirs(cache_dir, exist_ok=True)
    out = os.path.join(cache_dir, urllib.parse.quote(book_id, safe='') + '.png')
    if os.path.exists(out):
        return 'cached'
    if ext == 'epub': return generate_epub_cover(path, out)
    if ext == 'pdf':  return generate_pdf_cover(path, out)
    if ext == 'cbz':  return generate_cbz_cover(path, out)
    return 'no-cover'

ext = os.path.splitext(filepath)[1].lower().lstrip('.')

ok, reason = check_integrity(filepath, ext)
if not ok:
    print(f"CORRUPT\tskipped\t\t{reason}")
    sys.exit(0)

if ext == 'epub':
    book_id, title, authors, language, publisher = get_epub_info(filepath)
else:
    book_id   = md5_id(filepath)
    title     = os.path.splitext(os.path.basename(filepath))[0]
    authors, language, publisher = None, None, None

try:
    with open(lib_file) as f:
        data = json.load(f)
except Exception:
    data = {'uris': []}

if book_id in {pair[0] for pair in data.get('uris', [])}:
    cover = make_cover(filepath, ext, book_id)
    print(f"SKIP\t{cover}\t{book_id}\t{title or ''}")
    sys.exit(0)

if not dry_run:
    tilde_path = ('~' + filepath[len(home):]) if filepath.startswith(home) else filepath
    data['uris'].append([book_id, tilde_path])
    with open(lib_file, 'w') as f:
        json.dump(data, f, ensure_ascii=False)

    encoded = urllib.parse.quote(book_id, safe='')
    metadata = {
        "metadata": {
            "title": title, "author": authors, "contributor": None,
            "language": language, "publisher": publisher,
            "subject": None, "identifier": book_id, "source": None, "rights": None
        },
        "progress": [None, None],
        "lastLocation": None
    }
    meta_path = os.path.join(data_dir, f"{encoded}.json")
    if not os.path.exists(meta_path):
        with open(meta_path, 'w') as f:
            json.dump(metadata, f, ensure_ascii=False)

cover = make_cover(filepath, ext, book_id)
print(f"ADD\t{cover}\t{book_id}\t{title or ''}")
PYEOF
}

# ─── Find books ───────────────────────────────────────────────────────────────

build_find_args() {
    local args=("$BOOKS_DIR" -type f "(")
    local first=true
    for ext in "${EXTENSIONS[@]}"; do
        [[ "$first" == true ]] && first=false || args+=("-o")
        args+=("-iname" "*.${ext}")
    done
    args+=(")")
    printf '%s\0' "${args[@]}"
}

mapfile -d '' FIND_ARGS < <(build_find_args)
mapfile -t BOOK_FILES  < <(find "${FIND_ARGS[@]}" | sort)

total=${#BOOK_FILES[@]}
pad=${#total}

# ─── Header ───────────────────────────────────────────────────────────────────

if [[ "$QUIET" == false ]]; then
    printf "${C_BOLD}%-20s${C_RESET} %s\n" "${L_HDR_BDIR}:" "$BOOKS_DIR"
    printf "${C_BOLD}%-20s${C_RESET} %s\n" "${L_HDR_EXT}:"  "${EXTENSIONS[*]}"
    [[ "$GEN_COVERS" == true  ]] && printf "${C_BOLD}%-20s${C_RESET} %s px\n" "${L_HDR_COV_ON}:"  "$COVER_WIDTH"
    [[ "$GEN_COVERS" == false ]] && printf "${C_BOLD}%-20s${C_RESET}\n" "${L_HDR_COV_OFF}"
    [[ "$DRY_RUN"    == true  ]] && printf "${C_BOLD}%-20s${C_RESET}\n" "${L_HDR_DRY}"
    [[ "$QUIET"      == true  ]] && printf "${C_BOLD}%-20s${C_RESET}\n" "${L_HDR_QUIET}"
    echo ""
fi

if [[ $total -eq 0 ]]; then
    echo "$L_NO_BOOKS '$BOOKS_DIR'"
    exit 0
fi

# ─── Main loop ────────────────────────────────────────────────────────────────

added=0; skipped=0; covers_gen=0; cover_errors=0; corrupt=0; errors=0; idx=0

for book in "${BOOK_FILES[@]}"; do
    (( idx++ )) || true
    rel="${book#"$BOOKS_DIR"/}"
    counter="[$(printf "%${pad}d" $idx)/${total}]"

    result=$(import_book "$book" 2>/dev/null) || {
        [[ "$QUIET" == false ]] && \
            printf "${C_RED}%s ✗ %s${C_RESET}\n" "$counter" "$rel"
        (( errors++ )) || true
        continue
    }

    IFS=$'\t' read -r lib_st cover_st book_id book_title <<< "$result"

    case "$lib_st" in
        ADD)
            if [[ "$QUIET" == false ]]; then
                printf "${C_GREEN}%s ✓ %s${C_RESET}\n" "$counter" "$rel"
                [[ -n "$book_title" ]] && \
                    printf "    ${C_DIM}%-8s${C_RESET} %s\n" "${L_LBL_TITLE}:" "$book_title"
                printf "    ${C_DIM}%-8s${C_RESET} %s\n" "${L_LBL_ID}:" "$book_id"
                case "$cover_st" in
                    ok)       printf "    ${C_DIM}%-8s${C_RESET} ${C_GREEN}%s${C_RESET}\n" "${L_LBL_COVER}:" "$L_COV_GEN"
                              (( covers_gen++ )) || true ;;
                    cached)   printf "    ${C_DIM}%-8s${C_RESET} %s\n" "${L_LBL_COVER}:" "$L_COV_CACHED" ;;
                    no-cover) printf "    ${C_DIM}%-8s${C_RESET} ${C_DIM}%s${C_RESET}\n" "${L_LBL_COVER}:" "$L_COV_NONE" ;;
                    no-tool)  printf "    ${C_DIM}%-8s${C_RESET} ${C_YELLOW}%s${C_RESET}\n" "${L_LBL_COVER}:" "$L_COV_NO_TOOL" ;;
                    error)    printf "    ${C_DIM}%-8s${C_RESET} ${C_RED}%s${C_RESET}\n" "${L_LBL_COVER}:" "$L_COV_ERR"
                              (( cover_errors++ )) || true ;;
                esac
            else
                [[ "$cover_st" == "ok"    ]] && (( covers_gen++    )) || true
                [[ "$cover_st" == "error" ]] && (( cover_errors++  )) || true
            fi
            (( added++ )) || true
            ;;
        SKIP)
            if [[ "$cover_st" == "ok" ]]; then
                [[ "$QUIET" == false ]] && \
                    printf "${C_CYAN}%s → %s  ${C_DIM}[%s]${C_RESET}\n" \
                           "$counter" "$rel" "$L_COV_SKIP_TAG"
                (( covers_gen++ )) || true
            elif [[ "$cover_st" == "error" ]]; then
                [[ "$QUIET" == false ]] && \
                    printf "${C_RED}%s → %s  ${C_DIM}[%s]${C_RESET}\n" \
                           "$counter" "$rel" "$L_COV_ERR"
                (( cover_errors++ )) || true
            else
                [[ "$QUIET" == false ]] && \
                    printf "${C_DIM}%s → %s${C_RESET}\n" "$counter" "$rel"
            fi
            (( skipped++ )) || true
            ;;
        CORRUPT)
            [[ "$QUIET" == false ]] && \
                printf "${C_RED}%s ✗ %s  ${C_DIM}(%s: %s)${C_RESET}\n" \
                       "$counter" "$rel" "$L_CORRUPT" "$book_title"
            (( corrupt++ )) || true
            ;;
        *)
            [[ "$QUIET" == false ]] && \
                printf "${C_RED}%s ✗ %s${C_RESET}\n" "$counter" "$rel"
            (( errors++ )) || true
            ;;
    esac
done

# ─── Check removals ───────────────────────────────────────────────────────────

REMOVED_COUNT=0

check_removals() {
    [[ ! -f "$LIBRARY_FILE" ]] && return

    local missing_list
    missing_list=$(python3 - "$LIBRARY_FILE" "$FOLIATE_DATA" <<'PYEOF'
import sys, os, json, urllib.parse

lib_file = sys.argv[1]
data_dir = sys.argv[2]
home     = os.path.expanduser('~')

try:
    with open(lib_file) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

for entry in data.get('uris', []):
    if len(entry) < 2:
        continue
    book_id, tilde_path = entry[0], entry[1]
    real_path = (home + tilde_path[1:]) if tilde_path.startswith('~') else tilde_path
    if not os.path.exists(real_path):
        encoded = urllib.parse.quote(book_id, safe='')
        meta_file = os.path.join(data_dir, f'{encoded}.json')
        title = ''
        try:
            with open(meta_file) as f:
                meta = json.load(f)
            title = (meta.get('metadata') or {}).get('title') or ''
        except Exception:
            pass
        print(f"{book_id}\t{tilde_path}\t{title}")
PYEOF
    ) || true

    [[ -z "$missing_list" ]] && return

    echo ""
    printf "${C_YELLOW}${C_BOLD}%s${C_RESET}\n" "$L_MISS_HDR"

    local ids_to_remove=()

    while IFS=$'\t' read -r book_id tilde_path title; do
        echo ""
        printf "  ${C_YELLOW}%s${C_RESET}" "$tilde_path"
        [[ -n "$title" ]] && printf "  ${C_DIM}(%s: %s)${C_RESET}" "$L_LBL_TITLE" "$title"
        echo ""

        if [[ "$DRY_RUN" == true ]]; then
            printf "  ${C_DIM}%s${C_RESET}\n" "$L_MISS_DRY"
            continue
        fi

        printf "%s" "$L_MISS_PROMPT"
        read -r resp </dev/tty
        if [[ "${resp,,}" == "y" || "${resp,,}" == "${L_CLEAN_YES,,}" ]]; then
            ids_to_remove+=("$book_id")
            printf "  ${C_GREEN}✓ %s${C_RESET}\n" "$L_MISS_REMOVED"
        else
            printf "  ${C_DIM}→ %s${C_RESET}\n" "$L_MISS_KEPT"
        fi
    done <<< "$missing_list"

    [[ ${#ids_to_remove[@]} -eq 0 ]] && return

    REMOVED_COUNT=${#ids_to_remove[@]}

    python3 - "$LIBRARY_FILE" "$FOLIATE_DATA" "$FOLIATE_CACHE" "${ids_to_remove[@]}" <<'PYEOF2'
import sys, os, json, urllib.parse

lib_file  = sys.argv[1]
data_dir  = sys.argv[2]
cache_dir = sys.argv[3]
remove_ids = set(sys.argv[4:])

try:
    with open(lib_file) as f:
        data = json.load(f)
    data['uris'] = [e for e in data.get('uris', []) if not (e and e[0] in remove_ids)]
    with open(lib_file, 'w') as f:
        json.dump(data, f, ensure_ascii=False)
except Exception:
    pass

for book_id in remove_ids:
    encoded = urllib.parse.quote(book_id, safe='')
    for path in [
        os.path.join(data_dir, f'{encoded}.json'),
        os.path.join(cache_dir, f'{encoded}.png'),
    ]:
        try:
            os.unlink(path)
        except Exception:
            pass
PYEOF2
}

check_removals

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
printf '%s\n' "────────────────────────────────────────────────────────"
printf "${C_BOLD}%-24s${C_RESET} %d\n" "${L_SUM_TOTAL}:"   "$total"
printf "${C_BOLD}%-24s${C_RESET} %d\n" "${L_SUM_ADDED}:"   "$added"
printf "${C_BOLD}%-24s${C_RESET} %d\n" "${L_SUM_COV}:"     "$covers_gen"
printf "${C_BOLD}%-24s${C_RESET} %d\n" "${L_SUM_SKIP}:"    "$skipped"
[[ $REMOVED_COUNT  -gt 0 ]] && \
    printf "${C_YELLOW}${C_BOLD}%-24s${C_RESET} %d\n" "${L_SUM_REMOVED}:"   "$REMOVED_COUNT"
[[ $cover_errors -gt 0 ]] && \
    printf "${C_RED}${C_BOLD}%-24s${C_RESET} %d\n" "${L_SUM_COV_ERR}:" "$cover_errors"
[[ $corrupt -gt 0 ]] && \
    printf "${C_RED}${C_BOLD}%-24s${C_RESET} %d\n" "${L_SUM_CORRUPT}:" "$corrupt"
[[ $errors  -gt 0 ]] && \
    printf "${C_RED}${C_BOLD}%-24s${C_RESET} %d\n" "${L_SUM_ERR}:"     "$errors"

echo ""
printf "${C_BOLD}%s${C_RESET}\n" "$L_PATHS_HDR"
printf "  %-16s %s\n" "${L_PATH_CFG}:"  "$(tildify "$CONFIG_FILE")"
printf "  %-16s %s\n" "${L_PATH_CAT}:"  "$(tildify "$LIBRARY_FILE")"
printf "  %-16s %s/{id}.json\n" "${L_PATH_META}:" "$(tildify "$FOLIATE_DATA")"
printf "  %-16s %s/{id}.png\n"  "${L_PATH_COV}:"  "$(tildify "$FOLIATE_CACHE")"

if [[ "$DRY_RUN" == false && $(( added + covers_gen + REMOVED_COUNT )) -gt 0 ]]; then
    echo ""
    printf "${C_DIM}%s${C_RESET}\n" "$L_NOTE"
fi

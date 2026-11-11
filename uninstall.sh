#!/bin/bash
# Edited by Riley Porter 11/11/26
# Removes: HOMER, A.C.R.suite, IDR (source tree + installed copy, pip or old egg),
# R user library, Makevars.portable, and the PATH/R_LIBS_USER lines in ~/.bashrc.
#
# Optional: --python also uninstalls blosc, contourpy, matplotlib from ~/.local.
# Off by default because those live in your shared ~/.local user site and
# other projects may use them.

set -Eeuo pipefail
trap 'echo "!!! FAILED at line $LINENO (exit code $?)" >&2' ERR

REMOVE_PYTHON=0
for arg in "$@"; do
  case "$arg" in
    --python) REMOVE_PYTHON=1 ;;
    *) echo "Unknown option: $arg (valid: --python)" >&2; exit 2 ;;
  esac
done

# Load modules if available (needed for R version detection and pip)
if command -v module >/dev/null 2>&1; then
  module load shared rc-base GCCcore/13.2.0 R Anaconda3 2>/dev/null || true
fi

# R user library: derive from the loaded R version, fall back to 4.4
R_LIBS_USER_PATH=""
if command -v Rscript >/dev/null 2>&1; then
  R_LIBS_USER_PATH="$(Rscript --vanilla -e 'cat(file.path(Sys.getenv("HOME"), "R", paste0(R.version$platform, "-library"), paste0(R.version$major, ".", sub("\\..*", "", R.version$minor))))' 2>/dev/null || true)"
fi
if [ -z "$R_LIBS_USER_PATH" ]; then
  R_LIBS_USER_PATH="$HOME/R/x86_64-pc-linux-gnu-library/4.4"
  echo "Could not detect R version; falling back to $R_LIBS_USER_PATH"
fi

MAKEVARS_PORTABLE="$HOME/.R/Makevars.portable"
HOMER_DIR="$HOME/software/homer"
ACRSUITE_DIR="$HOME/software/A.C.R.suite"
IDR_DIR="$HOME/software/idr-2.0.2"
PYSITE="$HOME/.local/lib/python3.11/site-packages"

echo "=== Uninstall starting ==="
echo "This will remove:"
echo "  - $HOMER_DIR"
echo "  - $ACRSUITE_DIR"
echo "  - $IDR_DIR"
echo "  - installed IDR (~/.local/bin/idr, pip package, and old .egg if present)"
echo "  - $R_LIBS_USER_PATH"
echo "  - $MAKEVARS_PORTABLE"
echo "  - matching PATH/R_LIBS_USER lines from ~/.bashrc"
[ "$REMOVE_PYTHON" -eq 1 ] && echo "  - python packages: blosc, contourpy, matplotlib (--python)"
echo

remove_dir() {
  local d="$1"
  # Safety: must be non-empty, under $HOME, and not $HOME itself
  case "$d" in
    "$HOME"/?*) ;;
    *) echo "Refusing to remove suspicious path: '$d'" >&2; return 1 ;;
  esac
  if [ -d "$d" ]; then
    rm -rf "$d"
    echo "Removed: $d"
  else
    echo "Not found (skipping): $d"
  fi
}

remove_dir "$HOMER_DIR"
remove_dir "$ACRSUITE_DIR"
remove_dir "$IDR_DIR"
remove_dir "$R_LIBS_USER_PATH"

# --- Installed IDR (new pip install or old setup.py egg install) ---
if command -v pip3.11 >/dev/null 2>&1 && pip3.11 show idr >/dev/null 2>&1; then
  pip3.11 uninstall -y idr || true
fi

for egg in "$PYSITE"/idr-2.0.2-*.egg; do
  [ -e "$egg" ] || continue
  rm -rf "$egg"
  echo "Removed: $egg"
done

if [ -f "$PYSITE/easy-install.pth" ] && grep -q 'idr-2.0.2' "$PYSITE/easy-install.pth"; then
  cp "$PYSITE/easy-install.pth" "$PYSITE/easy-install.pth.bak.$(date +%Y%m%d_%H%M%S)"
  grep -v 'idr-2.0.2' "$PYSITE/easy-install.pth" > "$PYSITE/easy-install.pth.tmp" || true
  mv "$PYSITE/easy-install.pth.tmp" "$PYSITE/easy-install.pth"
  echo "Removed idr entry from easy-install.pth (backup saved)"
fi

if [ -e "$HOME/.local/bin/idr" ]; then
  rm -f "$HOME/.local/bin/idr"
  echo "Removed: $HOME/.local/bin/idr"
fi

# --- Optional python packages ---
if [ "$REMOVE_PYTHON" -eq 1 ]; then
  if command -v pip3.11 >/dev/null 2>&1; then
    for pkg in matplotlib contourpy blosc; do
      if pip3.11 show "$pkg" >/dev/null 2>&1; then
        pip3.11 uninstall -y "$pkg" || true
      else
        echo "Python package not installed (skipping): $pkg"
      fi
    done
  else
    echo "pip3.11 not found; skipping python package removal"
  fi
else
  echo "Leaving python packages (blosc/contourpy/matplotlib) in place; use --python to remove"
fi

# --- Makevars.portable ---
if [ -f "$MAKEVARS_PORTABLE" ]; then
  rm -f "$MAKEVARS_PORTABLE"
  echo "Removed: $MAKEVARS_PORTABLE"
else
  echo "Not found (skipping): $MAKEVARS_PORTABLE"
fi

if [ -d "$HOME/.R" ] && [ -z "$(ls -A "$HOME/.R")" ]; then
  rmdir "$HOME/.R"
  echo "Removed empty dir: $HOME/.R"
fi

# --- ~/.bashrc cleanup ---
if [ -f "$HOME/.bashrc" ]; then
  cp "$HOME/.bashrc" "$HOME/.bashrc.bak.$(date +%Y%m%d_%H%M%S)"
  echo "Backed up ~/.bashrc"

  BASHRC_PATH_LINE='export PATH="$HOME/software/homer/bin:$HOME/software/A.C.R.suite:$PATH"'
  # Matches both the old literal-$HOME form and the new expanded-path form,
  # for any R version: export R_LIBS_USER=".../R/<platform>-library/<X.Y>"
  RLIBS_REGEX='^export R_LIBS_USER="[^"]*/R/[^"/]*-library/[0-9]+\.[0-9]+"$'

  tmpfile="$(mktemp)"
  # `|| true`: grep -v exits 1 when it outputs nothing (e.g. file had only these lines)
  { grep -vxF "$BASHRC_PATH_LINE" "$HOME/.bashrc" || true; } \
    | { grep -vE "$RLIBS_REGEX" || true; } > "$tmpfile"
  mv "$tmpfile" "$HOME/.bashrc"
  echo "Removed PATH/R_LIBS_USER lines from ~/.bashrc (if present)"
else
  echo "No ~/.bashrc found (skipping bashrc cleanup)"
fi

echo
echo "=== Uninstall complete ==="
echo "Open a new shell (or 'source ~/.bashrc') so PATH changes take effect."

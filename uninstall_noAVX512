#!/bin/bash
# Edited by Riley Porter 1/30/26
# Removes: HOMER, A.C.Rsuite, IDR source tree, R user library (4.4), Makevars.portable,
# and the PATH/R_LIBS_USER lines appended to ~/.bashrc.
#
# NOTE: This will NOT reliably uninstall the python packages installed with --user
# (blosc/Cython/matplotlib), because those installs go into your ~/.local user site
# and may be used by other projects. This script leaves them alone by default.

set -euo pipefail

# Paths used by the installer
R_LIBS_USER_PATH="$HOME/R/x86_64-pc-linux-gnu-library/4.4"
MAKEVARS_PORTABLE="$HOME/.R/Makevars.portable"
HOMER_DIR="$HOME/software/homer"
ACRSUITE_DIR="$HOME/software/A.C.Rsuite"
IDR_DIR="$HOME/software/idr-2.0.2"

# Lines the installer appended to ~/.bashrc
BASHRC_PATH_LINE='export PATH="$HOME/software/homer/bin:$HOME/software/A.C.Rsuite:$PATH"'
BASHRC_RLIBS_LINE='export R_LIBS_USER="$HOME/R/x86_64-pc-linux-gnu-library/4.4"'

echo "=== Uninstall starting ==="
echo "This will remove:"
echo "  - $HOMER_DIR"
echo "  - $ACRSUITE_DIR"
echo "  - $IDR_DIR"
echo "  - $R_LIBS_USER_PATH"
echo "  - $MAKEVARS_PORTABLE"
echo "  - matching PATH/R_LIBS_USER lines from ~/.bashrc"
echo

# Remove installed directories
if [ -d "$HOMER_DIR" ]; then
  rm -rf "$HOMER_DIR"
  echo "Removed: $HOMER_DIR"
else
  echo "Not found (skipping): $HOMER_DIR"
fi

if [ -d "$ACRSUITE_DIR" ]; then
  rm -rf "$ACRSUITE_DIR"
  echo "Removed: $ACRSUITE_DIR"
else
  echo "Not found (skipping): $ACRSUITE_DIR"
fi

if [ -d "$IDR_DIR" ]; then
  rm -rf "$IDR_DIR"
  echo "Removed: $IDR_DIR"
else
  echo "Not found (skipping): $IDR_DIR"
fi

# Remove R user library (4.4)
if [ -d "$R_LIBS_USER_PATH" ]; then
  rm -rf "$R_LIBS_USER_PATH"
  echo "Removed: $R_LIBS_USER_PATH"
else
  echo "Not found (skipping): $R_LIBS_USER_PATH"
fi

# Remove Makevars.portable
if [ -f "$MAKEVARS_PORTABLE" ]; then
  rm -f "$MAKEVARS_PORTABLE"
  echo "Removed: $MAKEVARS_PORTABLE"
else
  echo "Not found (skipping): $MAKEVARS_PORTABLE"
fi

# If ~/.R is now empty, remove it (optional cleanup)
if [ -d "$HOME/.R" ] && [ -z "$(ls -A "$HOME/.R")" ]; then
  rmdir "$HOME/.R"
  echo "Removed empty dir: $HOME/.R"
fi

# Remove the appended lines from ~/.bashrc
if [ -f "$HOME/.bashrc" ]; then
  # Backup first
  cp "$HOME/.bashrc" "$HOME/.bashrc.bak.$(date +%Y%m%d_%H%M%S)"
  echo "Backed up ~/.bashrc"

  # Remove exact matching lines
  tmpfile="$(mktemp)"
  grep -vxF "$BASHRC_PATH_LINE" "$HOME/.bashrc" | grep -vxF "$BASHRC_RLIBS_LINE" > "$tmpfile"
  mv "$tmpfile" "$HOME/.bashrc"
  echo "Removed PATH/R_LIBS_USER lines from ~/.bashrc (if present)"
else
  echo "No ~/.bashrc found (skipping bashrc cleanup)"
fi

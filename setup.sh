#!/bin/bash
#SBATCH --job-name=setup
#SBATCH --cpus-per-task=8
#SBATCH --partition=medium
#SBATCH --mem=32G
#SBATCH --time=12:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#
# Edited by Riley Porter 11/11/26
# Re-runnable: skips anything already installed, and ends with a verification
# step that exits non-zero if anything is missing.

set -Eeuo pipefail
trap 'echo "!!! FAILED at line $LINENO (exit code $?)" >&2' ERR

step() { echo; echo "=== [$(date '+%F %T')] $* ==="; }

# Python version used for IDR / matplotlib (this setup used 3.10)
PY_VER="${PY_VER:-3.10}"
PY="python${PY_VER}"
PIP="pip${PY_VER}"

# HOMER genomes to install
HOMER_GENOMES=(mm10 hg38)

# ---------------------------------------------------------------------------
step "Loading modules"
# ---------------------------------------------------------------------------
module load shared rc-base
module load GCCcore/13.2.0
module load R
module load Anaconda3

# Parallelism (falls back to 1 outside Slurm)
NCPUS="${SLURM_CPUS_PER_TASK:-1}"
export NCPUS
export MAKEFLAGS="-j${NCPUS}"

# User library path derived from the loaded R version (not hardcoded to 4.4)
R_LIBS_USER="$(Rscript --vanilla -e 'cat(file.path(Sys.getenv("HOME"), "R", paste0(R.version$platform, "-library"), paste0(R.version$major, ".", sub("\\..*", "", R.version$minor))))')"
export R_LIBS_USER
mkdir -p "$R_LIBS_USER"
echo "R_LIBS_USER = $R_LIBS_USER"
echo "NCPUS       = $NCPUS"

# Prevent Tk/X11 issues on headless nodes
export R_DISABLE_TK=1

# Make sure user-installed Python scripts (idr) are found
export PATH="$HOME/.local/bin:$HOME/software/homer/bin:$HOME/software/A.C.R.suite:$PATH"

# ---------------------------------------------------------------------------
step "HOMER"
# ---------------------------------------------------------------------------
HOMER_DIR="$HOME/software/homer"
FRESH_HOMER=0
if [ ! -x "$HOMER_DIR/bin/findMotifsGenome.pl" ]; then
  mkdir -p "$HOMER_DIR"
  wget -nc http://homer.ucsd.edu/homer/configureHomer.pl -P "$HOMER_DIR"
  ( cd "$HOMER_DIR" && perl configureHomer.pl -install )
  FRESH_HOMER=1
else
  echo "HOMER base already installed, skipping"
fi

for genome in "${HOMER_GENOMES[@]}"; do
  if [ ! -d "$HOMER_DIR/data/genomes/$genome" ]; then
    ( cd "$HOMER_DIR" && perl configureHomer.pl -install "$genome" )
  else
    echo "HOMER genome $genome already installed, skipping"
  fi
done

if [ "$FRESH_HOMER" -eq 1 ]; then
  ( cd "$HOMER_DIR" && perl configureHomer.pl -update )
fi

# ---------------------------------------------------------------------------
step "A.C.R.suite"
# ---------------------------------------------------------------------------
mkdir -p "$HOME/software"
if [ ! -d "$HOME/software/A.C.R.suite" ]; then
  ( cd "$HOME/software" && git clone https://github.com/rwporter/A.C.R.suite.git )
else
  echo "A.C.R.suite already present, skipping"
fi

# ---------------------------------------------------------------------------
step "Python packages (pinned, binary wheels only)"
# ---------------------------------------------------------------------------
# contourpy 1.3.3 failed to build from source on the sibling cluster (no compatible
# wheel + old pybind11), so it is pinned to 1.3.2 here as well. matplotlib 3.10.x
# is used because it supports Python 3.10. Bump these deliberately.
"$PIP" install --user --only-binary=:all: \
  "blosc==1.11.4" \
  "Cython==3.0.4" \
  "contourpy==1.3.2" \
  "matplotlib==3.10.3"

# ---------------------------------------------------------------------------
step "IDR 2.0.2"
# ---------------------------------------------------------------------------
if [ ! -x "$HOME/.local/bin/idr" ]; then
  mkdir -p "$HOME/software"
  wget -nc https://github.com/nboley/idr/archive/2.0.2.zip -P "$HOME/software/"
  ( cd "$HOME/software" && unzip -o 2.0.2.zip && rm -f 2.0.2.zip )

  cp "$HOME/software/A.C.R.suite/idr.py" "$HOME/software/idr-2.0.2/idr/"

  # pip-based install replaces the deprecated `setup.py install`.
  # --no-build-isolation: setup.py needs the already-installed Cython.
  # --no-deps: numpy/scipy come from the SciPy-bundle module.
  ( cd "$HOME/software/idr-2.0.2" && \
    "$PIP" install --user --no-build-isolation --no-deps . )
else
  echo "IDR already installed, skipping"
fi

# ---------------------------------------------------------------------------
step "Persisting PATH + R_LIBS_USER in ~/.bashrc"
# ---------------------------------------------------------------------------
PATH_LINE='export PATH="$HOME/software/homer/bin:$HOME/software/A.C.R.suite:$PATH"'
grep -qxF "$PATH_LINE" ~/.bashrc || echo "$PATH_LINE" >> ~/.bashrc

RLIB_LINE="export R_LIBS_USER=\"$R_LIBS_USER\""
grep -qxF "$RLIB_LINE" ~/.bashrc || echo "$RLIB_LINE" >> ~/.bashrc

# ---------------------------------------------------------------------------
step "R packages"
# ---------------------------------------------------------------------------
Rscript --vanilla - <<'RSCRIPT'
options(tcltk.ignore = TRUE)

user_lib <- Sys.getenv("R_LIBS_USER")
ncpus    <- as.integer(Sys.getenv("NCPUS", "1"))
dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(user_lib)

# CRAN mirror with fallback
mirrors <- c("https://mirrors.nics.utk.edu/cran/", "https://cloud.r-project.org")
repos <- NULL
for (m in mirrors) {
  ok <- tryCatch({
    con <- url(paste0(m, "/src/contrib/PACKAGES"), open = "rb")
    close(con)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (ok) { repos <- m; break }
}
if (is.null(repos)) stop("No reachable CRAN mirror")
cat("Using CRAN mirror:", repos, "\n")
options(repos = c(CRAN = repos), Ncpus = ncpus)

# Only install what is not already available
missing_pkgs <- function(p) p[!p %in% rownames(installed.packages())]

cran_install <- function(p) {
  p <- missing_pkgs(p)
  if (length(p)) install.packages(p, lib = user_lib, type = "source", Ncpus = ncpus)
}

# 1) Bootstrap installers
cran_install(c("BiocManager", "remotes"))

# 2) Bioconductor first (Vennerable depends on RBGL + graph)
bioc_pkgs <- missing_pkgs(c("DESeq2", "RBGL", "graph"))
if (length(bioc_pkgs)) {
  BiocManager::install(bioc_pkgs, ask = FALSE, update = FALSE,
                       lib = user_lib, Ncpus = ncpus)
}

# 3) Remaining CRAN packages (Vennerable is no longer on CRAN)
cran_install(c(
  "optparse", "ggplot2", "MASS", "pheatmap", "rlang", "grImport",
  "gridExtra", "RColorBrewer", "colorspace", "htmltab", "plotrix",
  "plot3D", "data.table", "dplyr"
))

# 4) Vennerable from GitHub, after its Bioconductor dependencies
if (!"Vennerable" %in% rownames(installed.packages())) {
  remotes::install_github("js229/Vennerable", lib = user_lib,
                          upgrade = "never", dependencies = NA)
}

# 5) Verify every package actually loads; fail loudly if not
all_pkgs <- c("BiocManager", "remotes", "DESeq2", "RBGL", "graph", "Vennerable",
              "optparse", "ggplot2", "MASS", "pheatmap", "rlang", "grImport",
              "gridExtra", "RColorBrewer", "colorspace", "htmltab", "plotrix",
              "plot3D", "data.table", "dplyr")
failed <- all_pkgs[!vapply(all_pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(failed)) {
  cat("\nR PACKAGES FAILED TO LOAD:", paste(failed, collapse = ", "), "\n")
  quit(status = 1)
}
cat("\nAll", length(all_pkgs), "R packages load OK\n")
RSCRIPT

# ---------------------------------------------------------------------------
step "Final verification"
# ---------------------------------------------------------------------------
FAIL=0
check() {  # check <label> <command...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  OK    $label"; else echo "  FAIL  $label"; FAIL=1; fi
}

check "HOMER findMotifsGenome.pl on PATH" command -v findMotifsGenome.pl
for genome in "${HOMER_GENOMES[@]}"; do
  check "HOMER genome $genome" test -d "$HOMER_DIR/data/genomes/$genome"
done
check "A.C.R.suite present"               test -d "$HOME/software/A.C.R.suite"
check "idr runs"                          idr --version
check "python: matplotlib imports"        "$PY" -c "import matplotlib"
check "python: blosc imports"             "$PY" -c "import blosc"

if [ "$FAIL" -ne 0 ]; then
  echo; echo "!!! Setup finished WITH FAILURES (see FAIL lines above)" >&2
  exit 1
fi
echo; echo "=== Setup complete: all checks passed ==="

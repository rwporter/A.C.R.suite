#!/bin/bash
# Edited by Riley Porter 1/30/26

set -euo pipefail

# Load required modules
module load shared rc-base
module load GCCcore/13.2.0
module load R
module load Anaconda3

# Define user library
export R_LIBS_USER="$HOME/R/x86_64-pc-linux-gnu-library/4.4"

# Prevent Tk/X11 issues on headless nodes
export R_DISABLE_TK=1

# Install HOMER
mkdir -p "$HOME/software/homer"
wget http://homer.ucsd.edu/homer/configureHomer.pl -P "$HOME/software/homer"
cd "$HOME/software/homer"
perl configureHomer.pl -install
perl configureHomer.pl -install mm10
perl configureHomer.pl -install rn6
perl configureHomer.pl -install hg38
perl configureHomer.pl -update
cd -

# Install A.C.R.suite
mkdir -p "$HOME/software"
cd "$HOME/software"
if [ ! -d "$HOME/software/A.C.R.suite" ]; then
  git clone https://github.com/rwporter/A.C.R.suite.git
fi
cd -

# Install IDR
cd "$HOME/software"
wget -nc https://github.com/nboley/idr/archive/2.0.2.zip
unzip -o 2.0.2.zip && rm -f 2.0.2.zip
cd "$HOME/software/idr-2.0.2"
cp -f "$HOME/software/A.C.R.suite/idr.py" "$HOME/software/idr-2.0.2/idr/"
python3 -m pip install --user blosc Cython matplotlib
python3 setup.py install --user
cd -

# Persist PATH + R_LIBS_USER in ~/.bashrc
grep -qxF 'export PATH="$HOME/software/homer/bin:$HOME/software/A.C.R.suite:$PATH"' ~/.bashrc || \
echo 'export PATH="$HOME/software/homer/bin:$HOME/software/A.C.R.suite:$PATH"' >> ~/.bashrc

grep -qxF 'export R_LIBS_USER="$HOME/R/x86_64-pc-linux-gnu-library/4.4"' ~/.bashrc || \
echo 'export R_LIBS_USER="$HOME/R/x86_64-pc-linux-gnu-library/4.4"' >> ~/.bashrc

# Install R packages from source
Rscript --vanilla -e '
  options(tcltk.ignore = TRUE)

  user_lib <- Sys.getenv("R_LIBS_USER")
  dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(user_lib)

  repos <- "https://mirrors.nics.utk.edu/cran/"

  # CRAN packages
  cran_pkgs <- c(
    "BiocManager",
    "optparse",
    "ggplot2",
    "MASS",
    "pheatmap",
    "rlang",
    "Vennerable",
    "grImport",
    "gridExtra",
    "RColorBrewer",
    "colorspace",
    "htmltab",
    "plotrix",
    "plot3D",
    "data.table",
    "dplyr"
  )

  install.packages(
    cran_pkgs,
    lib = user_lib,
    repos = repos,
    type = "source"
  )

  if (!requireNamespace("BiocManager", quietly = TRUE, lib.loc = user_lib)) {
    install.packages(
      "BiocManager",
      lib = user_lib,
      repos = repos,
      type = "source"
    )
  }

  # Bioconductor packages
  bioc_pkgs <- c(
    "DESeq2",
    "RBGL",
    "graph"
  )

  BiocManager::install(
    bioc_pkgs,
    ask = FALSE,
    update = FALSE,
    lib = user_lib
  )
'

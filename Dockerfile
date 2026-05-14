# 17.3-LTS rbase currently apt-installs R 4.5.3 on Ubuntu noble — newer than
# the runtime's documented R 4.4.2 → Bioc 3.22 (matches R 4.5).
FROM databricksruntime/rbase:17.3-LTS

USER root

# --- System libs (used by both Rserve and Bioconductor builds) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      libxml2-dev libssl-dev libcurl4-openssl-dev \
      libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev \
      libpng-dev libtiff-dev libjpeg-dev libcairo2-dev libxt-dev \
      libgsl-dev libnetcdf-dev \
      zlib1g-dev libbz2-dev liblzma-dev \
      libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# --- Python REPL + SQL display() deps ---
# --- Mirror DBR 17.3-LTS Python env so /databricks/python_shell/lib/dbruntime
#     imports resolve. pyspark is excluded — it's injected at cluster launch
#     and pinning it here would shadow the cluster's version.
COPY dbr-17.3-lts-requirements.txt /tmp/dbr-17.3-lts-requirements.txt
RUN set -eux; \
    PIP=/databricks/python3/bin/pip; \
    if [ ! -x "$PIP" ]; then \
      echo "ERROR: $PIP not found. /databricks contents:"; \
      ls -laR /databricks/ | head -200; \
      exit 1; \
    fi; \
    "$PIP" install --no-cache-dir -r /tmp/dbr-17.3-lts-requirements.txt

RUN /databricks/python3/bin/python -c "\
import IPython, ipykernel, traitlets, six, typing_extensions, setuptools, \
       distutils.version, numpy, pandas, pyarrow, grpc, grpc_status, \
       google.protobuf, requests; \
print('REPL deps OK')"

RUN set -eux; \
    mkdir -p /databricks/r/override-lib; \
    R --no-save -e '\
      install.packages("Rserve", \
        repos = "https://packagemanager.posit.co/cran/__linux__/noble/latest", \
        lib   = "/databricks/r/override-lib"); \
      v <- packageVersion("Rserve", lib.loc = "/databricks/r/override-lib"); \
      cat("Rserve override version:", as.character(v), "\n"); \
      stopifnot(v >= "1.8-16")'; \
    printf '%s\n' \
      '## Prepend Rserve override so DBR-bundled 1.8-15 does not win library() lookup.' \
      '.libPaths(c("/databricks/r/override-lib", .libPaths()))' \
      >> /etc/R/Rprofile.site

RUN R --no-save <<'RSCRIPT'
options(
  Ncpus = max(1L, parallel::detectCores() - 1L),
  repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest")
)
install.packages("pak")
pkgs <- c("sparklyr", "tidyverse", "devtools", "ggpubr")
pak::pkg_install(pkgs, ask = FALSE)
for (p in pkgs) {
  stopifnot(requireNamespace(p, quietly = TRUE))
  cat(sprintf("%-12s %s\n", p, as.character(packageVersion(p))))
}
RSCRIPT

# --- Bioconductor 3.22 (matches R 4.5) ---
RUN R --no-save <<'RSCRIPT'
options(
  Ncpus = max(1L, parallel::detectCores() - 1L),
  repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"),
  BioC_mirror = "https://packagemanager.posit.co/bioconductor"
)
install.packages("BiocManager")
BiocManager::install(version = "3.22", ask = FALSE, update = FALSE)
bioc_pkgs <- c(
  "minfi", "wateRmelon",
  "sesame", "methylclock", "EpiDISH",
  "DMRcate", "Gviz",
  "missMethyl", "limma",
  "IlluminaHumanMethylationEPICanno.ilm10b4.hg19",
  "IlluminaHumanMethylationEPICv2anno.20a1.hg38"
)
pak::pkg_install(paste0("bioc::", bioc_pkgs), ask = FALSE)
stopifnot(all(sapply(bioc_pkgs, requireNamespace, quietly = TRUE)))
RSCRIPT

# --- Verify the override is what gets loaded ---
RUN R --no-save -e '\
    p <- find.package("Rserve"); \
    v <- packageVersion("Rserve"); \
    cat("Rserve loaded from:", p, "version:", as.character(v), "\n"); \
    stopifnot(grepl("^/databricks/r/override-lib", p)); \
    stopifnot(v >= "1.8-16")'
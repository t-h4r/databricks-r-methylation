# 17.3-LTS rbase currently apt-installs R 4.5.3 on Ubuntu noble — newer than
# the runtime's documented R 4.4.2 → Bioc 3.22 (matches R 4.5).
FROM databricksruntime/rbase:17.3-LTS

USER root

# --- Python REPL + SQL display() deps ---
RUN set -eux; \
    PIP=/databricks/python3/bin/pip; \
    if [ ! -x "$PIP" ]; then \
      echo "ERROR: $PIP not found. /databricks contents:"; \
      ls -laR /databricks/ | head -200; \
      exit 1; \
    fi; \
    "$PIP" install --no-cache-dir \
        ipython==8.30.0 \
        ipykernel==6.29.5 \
        traitlets==5.14.3 \
        six==1.16.0 \
        numpy==2.1.3 \
        pandas==2.2.3 \
        pyarrow==19.0.1 \
        grpcio==1.67.0 \
        protobuf==5.29.4

RUN /databricks/python3/bin/python -c "import IPython, ipykernel, traitlets, six, numpy, pandas, pyarrow, grpc, google.protobuf; print('REPL deps OK')"

# --- System libs (used by both Rserve and Bioconductor builds) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      libxml2-dev libssl-dev libcurl4-openssl-dev \
      libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev \
      libpng-dev libtiff-dev libjpeg-dev libcairo2-dev libxt-dev \
      libgsl-dev libnetcdf-dev \
      zlib1g-dev libbz2-dev liblzma-dev \
 && rm -rf /var/lib/apt/lists/*

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

# --- Bioconductor 3.22 (matches R 4.5) ---
RUN R --no-save <<'EOF'
options(
  Ncpus = max(1L, parallel::detectCores() - 1L),
  repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"),
  BioC_mirror = "https://packagemanager.posit.co/bioconductor"
)
install.packages("BiocManager")
BiocManager::install(version = "3.22", ask = FALSE, update = FALSE)
BiocManager::install(c(
  "minfi", "wateRmelon"
), ask = FALSE, update = FALSE)
stopifnot(all(sapply(c(
  "minfi", "wateRmelon"
), requireNamespace, quietly = TRUE)))
EOF

# --- Verify the override is what gets loaded ---
RUN R --no-save -e '\
    p <- find.package("Rserve"); \
    v <- packageVersion("Rserve"); \
    cat("Rserve loaded from:", p, "version:", as.character(v), "\n"); \
    stopifnot(grepl("^/databricks/r/override-lib", p)); \
    stopifnot(v >= "1.8-16")'
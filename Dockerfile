# 17.3-LTS rbase ships R 4.5.3 → use Bioc 3.22
FROM databricksruntime/rbase:17.3-LTS

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      libxml2-dev libssl-dev libcurl4-openssl-dev \
      libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev \
      libpng-dev libtiff-dev libjpeg-dev libcairo2-dev libxt-dev \
      libgsl-dev libnetcdf-dev \
      zlib1g-dev libbz2-dev liblzma-dev \
 && rm -rf /var/lib/apt/lists/*

RUN R --no-save <<'EOF'
options(
  Ncpus = max(1L, parallel::detectCores() - 1L),
  repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"),
  BioC_mirror = "https://packagemanager.posit.co/bioconductor"
)
install.packages("BiocManager")
BiocManager::install(version = "3.22", ask = FALSE, update = FALSE)
BiocManager::install(c(
  "minfi", "wateRmelon",
  "IlluminaHumanMethylationEPICanno.ilm10b4.hg19",
  "IlluminaHumanMethylationEPICv2anno.20a1.hg38"
), ask = FALSE, update = FALSE)
stopifnot(all(sapply(c(
  "minfi", "wateRmelon",
  "IlluminaHumanMethylationEPICanno.ilm10b4.hg19",
  "IlluminaHumanMethylationEPICv2anno.20a1.hg38"
), requireNamespace, quietly = TRUE)))
EOF
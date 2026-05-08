# 17.3-LTS is the newest LTS at 08052026
FROM databricksruntime/rbase:17.3-LTS

USER root

# System libs for Bioc source builds
RUN apt-get update && apt-get install -y --no-install-recommends \
      libxml2-dev libssl-dev libcurl4-openssl-dev \
      libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev \
      libpng-dev libtiff-dev libjpeg-dev libcairo2-dev libxt-dev \
      libgsl-dev libnetcdf-dev \
      zlib1g-dev libbz2-dev liblzma-dev \
 && rm -rf /var/lib/apt/lists/*

RUN printf '%s\n' \
      'options(Ncpus = max(1L, parallel::detectCores() - 1L))' \
      'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"))' \
      'options(BioC_mirror = "https://packagemanager.posit.co/bioconductor")' \
      >> /etc/R/Rprofile.site

# Install BiocManager, then minfi + wateRmelon.
RUN R -e "install.packages('BiocManager')" \
 && R -e "BiocManager::install(version = '3.20', ask = FALSE, update = FALSE)" \
 && R -e "BiocManager::install(c( \
        'minfi', \
        'wateRmelon', \
        'methylclock', \
        'IlluminaHumanMethylationEPICanno.ilm10b4.hg19', \
        'IlluminaHumanMethylationEPICv2anno.20a1.hg38' \
      ), ask = FALSE, update = FALSE)" \
 && R -e "stopifnot(all(sapply(c('minfi','wateRmelon','methylclock','IlluminaHumanMethylationEPICanno.ilm10b4.hg19','IlluminaHumanMethylationEPICv2anno.20a1.hg38'), requireNamespace, quietly=TRUE)))"
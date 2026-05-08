# databricks-r-methylation

Custom Docker image for running R-based DNA methylation analysis on Azure Databricks. Built on top of `databricksruntime/rbase:17.3-LTS` with [minfi](https://bioconductor.org/packages/minfi/), [wateRmelon](https://bioconductor.org/packages/wateRmelon/), [methylclock](https://bioconductor.org/packages/methylclock/), and EPIC v1/v2 annotation packages baked in, so clusters don't reinstall them on restart.

## Links

- **Docker Hub**: [`thardianto/r-methylation`](https://hub.docker.com/r/thardianto/r-methylation)
- **Maintainer**: [@t-h4r](https://github.com/t-h4r)

## What's in the image

| Component | Version |
|---|---|
| Base image | `databricksruntime/rbase:17.3-LTS` |
| OS | Ubuntu 24.04 (noble) |
| R | 4.5.3 |
| Bioconductor | 3.22 |
| CRAN snapshot | Posit Package Manager (`__linux__/noble/latest`) |

R packages installed:

- `minfi` — methylation array preprocessing and QC
- `wateRmelon` — alternative normalization (BMIQ, dasen) and Horvath age estimation
- `methylclock` — wrappers for Horvath, Hannum, PhenoAge, GrimAge, and gestational clocks
- `IlluminaHumanMethylationEPICanno.ilm10b4.hg19` — EPIC v1 probe annotation
- `IlluminaHumanMethylationEPICv2anno.20a1.hg38` — EPIC v2 probe annotation

Plus the full Bioconductor dependency tree these pull in (Biostrings, GenomicRanges, limma, bumphunter, etc.).

## Why this exists

Installing minfi and wateRmelon on a fresh Databricks cluster takes 20–40 minutes because Bioconductor packages compile from source. Baking them into a custom image means cluster startup is just an image pull — packages are already on disk and `library(minfi)` works immediately, every time the cluster restarts.

## Repository layout

```
~/databricks-r-methylation/
├── .github/
│   └── workflows/
│       └── build.yml
├── Dockerfile
└── README.md
```

## How the image is built

This repo uses GitHub Actions to build the image on pushes to main (when Dockerfile changes) and pushes the result to thardianto/r-methylation:17.3-LTS on Docker Hub. 

To change what's installed, edit the `BiocManager::install(...)` call in the `Dockerfile`, commit, and push.

## Using the image on Azure Databricks

### One-time setup

A workspace admin must enable Databricks Container Services. Via the Databricks CLI:

```bash
databricks workspace-conf set-status --json '{"enableDcs": "true"}'
```

### Verifying it worked

Attach an R notebook and run:

```r
library(minfi)
library(wateRmelon)
library(methylclock)
library(IlluminaHumanMethylationEPICv2anno.20a1.hg38)
sessionInfo()
```

All four should load with no "package not found" errors.

## Usage notes

### Probe annotation lookup

The anno packages expose lookup tables directly:

```r
library(IlluminaHumanMethylationEPICv2anno.20a1.hg38)
locs  <- IlluminaHumanMethylationEPICv2anno.20a1.hg38::Locations      # chr, pos, strand
isl   <- IlluminaHumanMethylationEPICv2anno.20a1.hg38::Islands.UCSC   # CGI relationship
other <- IlluminaHumanMethylationEPICv2anno.20a1.hg38::Other          # gene names, etc.
```

Or via minfi:

```r
anno <- minfi::getAnnotation("IlluminaHumanMethylationEPICv2anno.20a1.hg38")
```

### EPICv2 probe ID suffixes

EPICv2 probes carry replicate suffixes (`cg00000029_BC11`, `cg00000029_TC11`). The annotation tables key on the suffixed form. If your beta matrix has bare `cg########` IDs, strip suffixes on both sides before joining, or you'll get NA-heavy lookups.

### Namespace collision between v1 and v2 anno

Both anno packages export objects called `Islands.UCSC`, `Locations`, `Manifest`, etc. Loading both in the same R session masks the first. Use the `pkg::object` form when you need both side by side.

## Updating the image

Edit `Dockerfile`, commit, push. Docker Hub rebuilds automatically. To force a cluster to pick up the new image, restart it.

For non-breaking updates, overwrite the `17.3-LTS` tag. For changes that might break downstream notebooks (R version bump, package removals, Bioc version change), use a new tag like `17.3-LTS-v2` and update the cluster config explicitly — easy rollback if something goes wrong.

## Troubleshooting

**"Image pull failed" on cluster start.** Image name typo, or the Docker Hub repo went private without updating cluster credentials.

**Cluster starts but R can't find packages.** Run `.libPaths()` in a notebook and check where R is looking. Then `%sh ls /usr/lib/R/site-library` to see where the build installed them. If they don't match, set `R_LIBS_SITE` as a cluster environment variable pointing at the install path.

**Build fails on Docker Hub with OOM.** Bioconductor source builds are heavy. The Dockerfile caps R's parallel compilation to keep memory bounded; if you've changed that, lower `options(Ncpus = ...)` in the Dockerfile.

**Need to inspect the image locally on Apple Silicon.** It runs under Rosetta emulation — slow but functional:

```bash
docker pull --platform linux/amd64 thardianto/r-methylation:17.3-LTS
docker run --rm -it --platform linux/amd64 thardianto/r-methylation:17.3-LTS bash
```

## References

- [Databricks Runtime 17.3 LTS release notes](https://learn.microsoft.com/en-us/azure/databricks/release-notes/runtime/17.3lts)
- [Customize containers with Databricks Container Service (Azure)](https://learn.microsoft.com/en-us/azure/databricks/compute/custom-containers)
- [Databricks for R developers](https://learn.microsoft.com/en-us/azure/databricks/sparkr/)
- [databricks/containers GitHub repo](https://github.com/databricks/containers) — source for the `databricksruntime/rbase` base image
- [Posit Package Manager](https://packagemanager.posit.co/) — CRAN and Bioconductor binary mirror used in the build
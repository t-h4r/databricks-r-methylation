# databricks-r-methylation

Custom Docker image for running R-based DNA methylation analysis on Azure Databricks. Built on top of `databricksruntime/rbase:17.3-LTS` with [minfi](https://bioconductor.org/packages/minfi/), [wateRmelon](https://bioconductor.org/packages/wateRmelon/), and EPIC v1/v2 annotation packages baked in. Also installs the Python deps and a patched Rserve needed for the Databricks notebook REPL and `%sql` cells to work — the stock rbase image is too minimal for either.

## Links

- **Docker Hub**: [`thardianto/r-methylation`](https://hub.docker.com/r/thardianto/r-methylation)
- **Maintainer**: [@t-h4r](https://github.com/t-h4r)

## What's in the image

| Component | Version | Notes |
|---|---|---|
| Base image | `databricksruntime/rbase:17.3-LTS` | |
| OS | Ubuntu 24.04 (noble) | |
| R | 4.5.3 | apt-installed from noble; newer than DBR runtime's documented 4.4.2 |
| Bioconductor | 3.22 | matches R 4.5 |
| Rserve override | ≥ 1.8-16 | installed to `/databricks/r/override-lib` and prepended via `Rprofile.site` — DBR's bundled 1.8-15 is incompatible with R 4.5's strict `R_getVarEx` check |
| Python | 3.12.3 | from the rbase base image |
| Python deps | DBR 17.3-LTS env (`dbr-17.3-lts-requirements.txt`) | full mirror of the runtime's Python env so `/databricks/python_shell/lib/dbruntime/*` imports resolve |
| CRAN snapshot | Posit Package Manager (`__linux__/noble/latest`) | |

R packages installed:

**Methylation analysis (Bioconductor):**

- `minfi` — methylation array preprocessing and QC
- `sesame` — alternative preprocessing pipeline with native EPIC v2 support
- `wateRmelon` — alternative normalization (BMIQ, dasen) and Horvath age estimation
- `methylclock` — DNA methylation age calculators (Horvath, Hannum, PhenoAge, etc.)
- `EpiDISH` — cell-type deconvolution from methylation data
- `DMRcate` — differentially methylated region detection
- `missMethyl` — differential methylation testing and gene-set enrichment (note: camelCase, `library(missmethyl)` will fail)
- `limma` — linear models for microarray analysis (also a transitive dep of several of the above)

**Probe annotation:**

- `IlluminaHumanMethylationEPICanno.ilm10b4.hg19` — EPIC v1
- `IlluminaHumanMethylationEPICv2anno.20a1.hg38` — EPIC v2

**Spark and data wrangling (CRAN):**

- `sparklyr` — dplyr-style interface to Spark for SQL from R
- `tidyverse` — `dplyr`, `tidyr`, `ggplot2`, `readr`, `purrr`, `stringr`, `forcats`, `tibble`, `lubridate`

Plus the full Bioconductor dependency tree these pull in (Biostrings, GenomicRanges, GenomicFeatures, bumphunter, etc.).

## Why this exists

Two reasons:

1. **Bake-in time.** Installing minfi and wateRmelon on a fresh Databricks cluster takes 20–40 minutes because Bioconductor packages compile from source. Baking them into a custom image means cluster startup is just an image pull — packages are already on disk and `library(minfi)` works immediately, every time the cluster restarts.
2. **Compatibility patches.** The stock `databricksruntime/rbase:17.3-LTS` is intentionally minimal and breaks against the DBR 17.3-LTS runtime in two ways:
   - Its R is at 4.5.3 (noble's current), but the runtime's bundled Rserve was built against R 4.4 and crashes immediately on R 4.5 with `first argument to 'R_getVarEx' must be a symbol`. This image installs a newer Rserve and forces R to load it ahead of the bundled one.
   - It ships almost no Python packages, but `db_ipykernel_launcher.py` and its `dbruntime` import chain expect ~190 of them. Without those, every Python and `%sql` cell fails at REPL startup. This image installs the full DBR 17.3-LTS Python env to match.

## Repository layout

```
~/databricks-r-methylation/
├── .github/
│   └── workflows/
│       └── build.yml
├── Dockerfile
├── dbr-17.3-lts-requirements.txt
└── README.md
```

## How the image is built

This repo uses GitHub Actions to build the image on pushes to main (when `Dockerfile` or `dbr-17.3-lts-requirements.txt` changes) and pushes the result to `thardianto/r-methylation:17.3-LTS` on Docker Hub.

To change what's installed:

- **R / Bioconductor packages** — edit the `install.packages(...)` and `BiocManager::install(...)` calls in the Dockerfile
- **Python packages** — edit `dbr-17.3-lts-requirements.txt`

Then commit and push.

## Using the image on Azure Databricks

### Cluster configuration gotcha

When you tick "Use your own Docker container" in the cluster create UI, **make sure the Databricks Runtime version selected is the non-ML, non-snapshot variant** (e.g. `17.3.x-scala2.13`). ML runtimes don't support DCS and snapshot blobs aren't durable — picking either gives an `INVALID_SPARK_IMAGE` / `X_InvalidSparkImage` failure at cluster bootstrap, before the container is even pulled.

### Verifying it worked

Attach a notebook and run these in separate cells:

```r
# R — Bioconductor methylation stack loads
pkgs <- c("minfi", "sesame", "wateRmelon", "methylclock", "EpiDISH",
          "DMRcate", "missMethyl", "limma",
          "IlluminaHumanMethylationEPICanno.ilm10b4.hg19",
          "IlluminaHumanMethylationEPICv2anno.20a1.hg38")
for (p in pkgs) library(p, character.only = TRUE)
sessionInfo()
```

```r
# R — Rserve override is live (path must be under /databricks/r/override-lib)
find.package("Rserve")
packageVersion("Rserve")
```

```r
# R — SQL via sparklyr
library(sparklyr)
sc <- spark_connect(method = "databricks")
DBI::dbGetQuery(sc, "SHOW DATABASES")
```

```python
# Python — REPL is alive and Spark is reachable
spark.sql("SHOW DATABASES").show()
```

```sql
-- %sql — result rendering works
SHOW DATABASES;
```

If `find.package("Rserve")` returns a path under `/databricks/spark/R/lib` instead of `/databricks/r/override-lib`, the override didn't win the library lookup — see Troubleshooting.

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

### Load order for SparkR vs dplyr/sparklyr

DBR injects `SparkR` into custom R sessions automatically. If you load `library(SparkR)` *after* `library(dplyr)` or `library(sparklyr)`, SparkR's `select`, `filter`, `collect`, `between`, etc. mask the dplyr versions — usually the wrong direction for a tidyverse workflow. Either load dplyr/sparklyr last, or namespace-qualify your verbs (`dplyr::filter(...)`) when ambiguity matters.

## Updating the image

Edit `Dockerfile` or `dbr-17.3-lts-requirements.txt`, commit, push. Docker Hub rebuilds automatically. To force a cluster to pick up the new image, restart it.

For non-breaking updates, overwrite the `17.3-LTS` tag. For changes that might break downstream notebooks (R version bump, package removals, Bioc version change), use a new tag like `17.3-LTS-v2` and update the cluster config explicitly — easy rollback if something goes wrong.

When DBR releases a new LTS, the Python env table in the [release notes](https://learn.microsoft.com/en-us/azure/databricks/release-notes/runtime/) will list new package versions. Regenerate `dbr-17.3-lts-requirements.txt` from that table — otherwise pinned versions may drift out of sync with the cluster's bundled `dbruntime` and you'll start hitting the same `ModuleNotFoundError` whack-a-mole this image was built to eliminate.

## Troubleshooting

**`INVALID_SPARK_IMAGE` / `X_InvalidSparkImage` at cluster start.** The cluster's `spark_version` is an ML runtime or a snapshot release. Switch to a stable non-ML variant like `17.3.x-scala2.13`. ML runtimes don't support DCS; snapshot blobs aren't durable, so 404s from Azure blob storage are expected. The image has nothing to do with this failure — it happens before the container is pulled.

**R REPL fails with `first argument to 'R_getVarEx' must be a symbol`.** The Rserve override didn't load. Check that `/etc/R/Rprofile.site` contains `.libPaths(c("/databricks/r/override-lib", .libPaths()))` and that `find.package("Rserve")` returns a path under that directory. If DBR's cluster-init mutated `.libPaths()` after `Rprofile.site` ran, the override can lose; in that case, move the path to `R_LIBS_USER` via `/etc/R/Renviron.site` instead.

**Python REPL fails with `ModuleNotFoundError: No module named '<X>'`.** The Python requirements file is missing a package the runtime's `dbruntime` import chain needs. Check the traceback in the driver `stderr.txt` (Compute → cluster → Driver logs) for the failing import and add it to `dbr-17.3-lts-requirements.txt`. The PyPI-name-to-import-name mapping isn't always obvious — common gotchas:

  | Import | PyPI package |
  |---|---|
  | `grpc` | `grpcio` |
  | `grpc_status` | `grpcio-status` |
  | `google.protobuf` | `protobuf` |
  | `IPython` | `ipython` |
  | `distutils.version` | `setuptools` (provides the shim on Python 3.12+) |

**`pip install` fails on `psycopg2` with `pg_config executable not found`.** The requirements file should use `psycopg2-binary==2.9.3`, not `psycopg2==2.9.3`. The source build needs `libpq-dev`; the binary wheel doesn't. Same Python API, no system dependency.

**Cluster starts but R can't find packages.** Run `.libPaths()` in a notebook and check where R is looking. Then `%sh ls /usr/lib/R/site-library` and `%sh ls /databricks/r/override-lib` to see where the build installed them. If they don't match, set `R_LIBS_SITE` as a cluster environment variable pointing at the install path.

**"Image pull failed" on cluster start.** Image name typo, or the Docker Hub repo went private without updating cluster credentials.

**Build fails with "dependencies ... are not available for package 'methylclock'".** methylclock declares `devtools`, `tidyverse`, and `ggpubr` in its `Depends` — all CRAN, not Bioc. The Dockerfile must install CRAN packages *before* the Bioconductor install step; if the order is reversed, BiocManager can't satisfy methylclock's deps and silently skips the install. Same pattern for any Bioc package that depends on CRAN-only packages.

**Build fails with "dependency 'Gviz' is not available for package 'DMRcate'".** Gviz is a Bioc package that DMRcate pulls transitively. BiocManager occasionally swallows install errors for transitive deps into its warnings bucket. List Gviz (or any other failing transitive Bioc dep) explicitly in the top-level `BiocManager::install(...)` call so the real error surfaces.

**Build fails on Docker Hub with OOM.** Bioconductor source builds are heavy. The Dockerfile caps R's parallel compilation to keep memory bounded; if you've changed that, lower `options(Ncpus = ...)` in the Dockerfile.

## References

- [Databricks Runtime 17.3 LTS release notes](https://learn.microsoft.com/en-us/azure/databricks/release-notes/runtime/17.3lts)
- [Customize containers with Databricks Container Service (Azure)](https://learn.microsoft.com/en-us/azure/databricks/compute/custom-containers)
- [Databricks for R developers](https://learn.microsoft.com/en-us/azure/databricks/sparkr/)
- [databricks/containers GitHub repo](https://github.com/databricks/containers) — source for the `databricksruntime/rbase` base image
- [Posit Package Manager](https://packagemanager.posit.co/) — CRAN and Bioconductor binary mirror used in the build
- [Rserve on rforge](http://www.rforge.net/Rserve/) — Rserve releases and NEWS
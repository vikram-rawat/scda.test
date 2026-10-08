# run_tests_locally.r --- Install deps & run tests locally -----
#
# Reads DESCRIPTION dynamically. Installs GitHub remotes first,
# then any missing CRAN deps. Verifies all packages load.
# Runs the full test suite. Works on Windows and Linux.

# Preflight ---- check pak -----------------------------------------------------

if (!requireNamespace("pak", quietly = TRUE)) {
  message("📦 Installing pak...")
  install.packages("pak")
}

# Packages used in tests but not listed in DESCRIPTION.
# Base R packages (grid, stats, tools, utils) are always available.
extra_pkgs <- c("readxl", "rlang", "stringi", "tidytlg", "vctrs", "testthat")
missing_extras <- extra_pkgs[
  !vapply(extra_pkgs, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_extras) > 0L) {
  message(sprintf(
    "📦 Installing %d unlisted deps: %s",
    length(missing_extras),
    paste(missing_extras, collapse = ", ")
  ))
  pak::pak(missing_extras, ask = FALSE)
}

# Helper ---- find repo root cross-platform -----------------------------------

find_repo_root <- function() {
  # Try git first
  root <- tryCatch(
    normalizePath(trimws(system2(
      "git",
      c("rev-parse", "--show-toplevel"),
      stdout = TRUE
    ))),
    warning = function(w) NULL,
    error = function(e) NULL
  )
  if (!is.null(root) && length(root) == 1L) {
    return(root)
  }

  # Fallback: walk up from working directory
  candidate <- getwd()
  while (!file.exists(file.path(candidate, "DESCRIPTION"))) {
    parent <- dirname(candidate)
    if (parent == candidate) {
      stop("🚨 Cannot find DESCRIPTION! Run from inside the repo.")
    }
    candidate <- parent
  }
  candidate
}

# Helper ---- parse a DESCRIPTION field into package names --------------------

# Handles both single-line (Depends: R, tern) and multi-line formats.
# Strips version constraints like (>= 1.0). Drops "R" (base).
parse_desc_field <- function(field, lines) {
  start <- grep(sprintf("^%s:", field), lines)
  if (length(start) == 0L) {
    return(character(0))
  }

  # Grab the first line content after the field name
  first_line <- sub(sprintf("^%s:\\s*", field), "", lines[start])
  field_lines <- first_line

  # Grab continuation lines (start with whitespace)
  i <- start + 1L
  while (i <= length(lines) && grepl("^\\s", lines[i])) {
    field_lines <- c(field_lines, trimws(lines[i]))
    i <- i + 1L
  }

  raw <- unlist(strsplit(paste(field_lines, collapse = " "), ","))
  pkgs <- trimws(gsub("\\(.*?\\)", "", raw))
  pkgs[nchar(pkgs) > 0L & pkgs != "R"]
}

# Helper ---- parse Remotes field into GitHub refs ----------------------------

parse_remotes <- function(lines) {
  start <- grep("^Remotes:", lines)
  if (length(start) == 0L) {
    return(character(0))
  }

  remotes_lines <- character(0)
  i <- start + 1L
  while (i <= length(lines) && grepl("^\\s", lines[i])) {
    remotes_lines <- c(remotes_lines, trimws(lines[i]))
    i <- i + 1L
  }

  refs <- gsub(",\\s*$", "", remotes_lines)
  refs[nchar(refs) > 0L]
}

# Parse ---- read DESCRIPTION -------------------------------------------------

repo_root <- find_repo_root()
desc_path <- file.path(repo_root, "DESCRIPTION")
desc_lines <- readLines(desc_path)

remotes_refs <- parse_remotes(desc_lines)
if (length(remotes_refs) == 0L) {
  stop("🚨 No Remotes: field found in DESCRIPTION!")
}

# Extract bare package names from remotes
# Handles: "org/pkg@branch", "org/pkg" (no branch), "org/pkg#123" (PR)
remotes_pkg_names <- tolower(gsub(".*/([^@#]+).*", "\\1", remotes_refs))

# Parse ALL dependency fields
dep_fields <- c("Depends", "Imports", "Suggests", "Enhances", "LinkingTo")
all_desc_pkgs <- unique(unlist(lapply(
  dep_fields,
  parse_desc_field,
  lines = desc_lines
)))

# Split: GitHub vs CRAN
cran_pkgs <- all_desc_pkgs[!tolower(all_desc_pkgs) %in% remotes_pkg_names]

# Install ---- GitHub remotes --------------------------------------------------

message(sprintf("📦 Installing %d GitHub packages...", length(remotes_refs)))
pak::pak(remotes_refs, ask = FALSE)

# Install ---- missing CRAN deps ----------------------------------------------

missing <- cran_pkgs[
  !vapply(cran_pkgs, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing) > 0L) {
  message(sprintf("📦 Installing %d missing CRAN deps...", length(missing)))
  pak::pak(missing, ask = FALSE)
}

# Verify ---- check ALL packages are loadable ----------------------------------

failed <- character(0)
for (pkg in all_desc_pkgs) {
  ok <- tryCatch(
    {
      packageVersion(pkg)
      TRUE
    },
    error = function(e) FALSE
  )
  if (!ok) failed <- c(failed, pkg)
}

if (length(failed) > 0L) {
  stop(sprintf(
    "🚨 %d package(s) not installed: %s",
    length(failed),
    paste(failed, collapse = ", ")
  ))
}

message(sprintf(
  "✅ All %d packages ready | R %s | %s",
  length(all_desc_pkgs),
  getRversion(),
  .Platform$OS.type
))

# Run ---- full test suite -----------------------------------------------------

message("🧪 Running tests...")
Sys.setenv(NOT_CRAN = "true")

testthat::test_dir(
  file.path(repo_root, "tests", "testthat"),
  reporter = testthat::default_reporter()
)

message("🎉 Done!")

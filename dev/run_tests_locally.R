# run_tests_locally.r --- Install deps & run tests locally -----
# Parses DESCRIPTION. Prioritizes Remotes (GitHub) over CRAN.
# Removes + reinstalls all Remotes for branch sync.
# Works on Windows and Linux. Run in a FRESH R session.

# Preflight ---- pak -----------------------------------------------------------

if (!requireNamespace("pak", quietly = TRUE)) {
  message("📦 Installing pak...")
  install.packages("pak")
}

# Helper ---- find repo root ---------------------------------------------------

find_repo_root <- function() {
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

  candidate <- getwd()
  while (!file.exists(file.path(candidate, "DESCRIPTION"))) {
    parent <- dirname(candidate)
    if (parent == candidate) {
      stop("🚨 Cannot find DESCRIPTION!")
    }
    candidate <- parent
  }
  candidate
}

# Helper ---- parse DESCRIPTION field ------------------------------------------

parse_desc_field <- function(field, lines) {
  start <- grep(sprintf("^%s:", field), lines)
  if (length(start) == 0L) {
    return(character(0))
  }

  first_line <- sub(sprintf("^%s:\\s*", field), "", lines[start])
  field_lines <- first_line
  i <- start + 1L
  while (i <= length(lines) && grepl("^\\s", lines[i])) {
    field_lines <- c(field_lines, trimws(lines[i]))
    i <- i + 1L
  }

  raw <- unlist(strsplit(paste(field_lines, collapse = " "), ","))
  pkgs <- trimws(gsub("\\(.*?\\)", "", raw))
  pkgs[nchar(pkgs) > 0L & pkgs != "R"]
}

# Helper ---- parse Remotes field ----------------------------------------------

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

# Extract pkg name: "org/pkg@branch/thing" -> "pkg"
remotes_pkg_names <- tolower(vapply(
  remotes_refs,
  function(ref) sub("@.*$", "", sub("^[^/]+/", "", ref)),
  character(1),
  USE.NAMES = FALSE
))

dep_fields <- c("Depends", "Imports", "Suggests", "Enhances", "LinkingTo")
all_desc_pkgs <- unique(unlist(lapply(
  dep_fields,
  parse_desc_field,
  lines = desc_lines
)))

cran_pkgs <- all_desc_pkgs[!tolower(all_desc_pkgs) %in% remotes_pkg_names]

# Remove ---- wipe Remotes packages (must run before any library() call) -------

# Check installed without loading (packageVersion reads DESCRIPTION on disk).
installed_remotes <- remotes_pkg_names[vapply(
  remotes_pkg_names,
  function(p) !inherits(tryCatch(packageVersion(p), error = identity), "error"),
  logical(1)
)]
if (length(installed_remotes) > 0L) {
  message(sprintf(
    "🗑️ Removing %d Remotes packages: %s",
    length(installed_remotes),
    paste(installed_remotes, collapse = ", ")
  ))
  suppressMessages(remove.packages(installed_remotes))
}

# Install ---- Remotes (fresh from GitHub) -------------------------------------

message(sprintf(
  "📦 Installing %d GitHub packages...",
  length(remotes_refs)
))
pak::pak(remotes_refs, ask = FALSE)

# Safety net ---- used in tests but not in DESCRIPTION ------------------------

extra_pkgs <- c("readxl", "rlang", "stringi", "tidytlg", "vctrs")
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

# Install ---- CRAN deps, only if missing --------------------------------------

missing_cran <- cran_pkgs[
  !vapply(cran_pkgs, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_cran) > 0L) {
  message(sprintf("📦 Installing %d CRAN deps...", length(missing_cran)))
  pak::pak(missing_cran, ask = FALSE)
}

# Verify ---- all packages loadable --------------------------------------------

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

# Run ---- attach Depends + run tests -----------------------------------------

# test_dir() doesn't auto-attach Depends like R CMD check does.
depends_pkgs <- parse_desc_field("Depends", desc_lines)
for (pkg in depends_pkgs) {
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

message("🧪 Running tests...")
Sys.setenv(NOT_CRAN = "true")

testthat::test_dir(
  file.path(repo_root, "tests", "testthat"),
  reporter = testthat::default_reporter()
)

message("🎉 Done!")

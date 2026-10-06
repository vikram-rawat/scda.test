# sync_upstream.r --- Sync main with upstream via scripts ------

# Config --- edit these if remotes change ----------------------

upstream <- "upstream"
branch <- "main"
dev_pattern <- "^dev/"

# Preflight --- check dependencies ----------------------------

if (!requireNamespace("glue", quietly = TRUE)) {
  stop("🚨 glue package not installed. Run: install.packages('glue')")
}

# Helper --- run git and stop on failure ----------------------

run_git <- function(...) {
  args <- c(...)
  result <- system2("git", args, stdout = TRUE, stderr = TRUE)
  status <- attr(result, "status")
  if (!is.null(status) && status != 0L) {
    stop(sprintf(
      "🚨 git %s failed:\n%s",
      paste(args, collapse = " "),
      paste(result, collapse = "\n")
    ))
  }
  invisible(result)
}

# Setup --- paths and OS detection ----------------------------

repo_root <- trimws(run_git("rev-parse", "--show-toplevel"))
setwd(repo_root)
message(sprintf("📁 Repo root: %s", repo_root))

scripts_dir <- file.path(repo_root, "dev", "scripts")
is_windows <- .Platform$OS.type == "windows"

# Preflight --- verify upstream remote exists -----------------

remotes <- run_git("remote")
if (!upstream %in% remotes) {
  stop(sprintf(
    "🚨 Remote '%s' not found. Run:\ngit remote add %s https://github.com/insightsengineering/scda.test.git",
    upstream, upstream
  ))
}

# Preflight --- must be on target branch ----------------------

current_branch <- trimws(run_git("branch", "--show-current"))
if (current_branch != branch) {
  message(sprintf("🔀 Switching from '%s' to '%s'...", current_branch, branch))
  run_git("checkout", branch)
}

# Template --- read and fill ----------------------------------

template_file <- if (is_windows) "sync_upstream.ps1" else "sync_upstream.sh"
template_path <- file.path(scripts_dir, template_file)

if (!file.exists(template_path)) {
  stop(sprintf("🚨 Template not found: %s", template_path))
}

filled_script <- glue::glue(
  readLines(template_path) |> paste(collapse = "\n"),
  upstream = upstream,
  branch = branch,
  .open = "{{",
  .close = "}}"
)

# Execute --- write to temp, run, show output ------------------

tmp <- tempfile(fileext = if (is_windows) ".ps1" else ".sh")
on.exit(unlink(tmp), add = TRUE)
writeLines(filled_script, tmp)

if (is_windows) {
  shell_cmd <- "powershell"
  shell_args <- c("-ExecutionPolicy", "Bypass", "-File", tmp)
} else {
  Sys.chmod(tmp, "755")
  shell_cmd <- "bash"
  shell_args <- tmp
}

message(sprintf("▶️  Running: %s %s", shell_cmd, basename(tmp)))

result <- system2(shell_cmd, shell_args, stdout = TRUE, stderr = TRUE)
status <- attr(result, "status")
if (is.null(status)) status <- 0L

cat(result, sep = "\n")

if (status != 0L) {
  stop(sprintf("❌ Sync failed (exit %d). Fix the template: %s", status, template_path))
}

message("✅ Sync complete! 🎉")

# Housekeeping --- re-add dev/ exclusion to .Rbuildignore ------

rbuildignore_path <- file.path(repo_root, ".Rbuildignore")
rbuildignore <- readLines(rbuildignore_path)

has_dev_entry <- any(grepl(dev_pattern, rbuildignore, fixed = TRUE))

if (!has_dev_entry) {
  message("🔧 Re-adding dev/ exclusion to .Rbuildignore...")
  writeLines(c(rbuildignore, dev_pattern), rbuildignore_path)
  run_git("add", ".Rbuildignore")
  run_git("commit", "--amend", "--no-edit")
  run_git("push", "origin", branch, "--force")
  message("📝 .Rbuildignore patched and pushed!")
} else {
  message("📝 .Rbuildignore already excludes dev/ — skipping.")
}

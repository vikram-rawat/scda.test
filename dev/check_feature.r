# check_feature.r --- Test a feature branch against scda.test --

# Config --- user inputs --------------------------------------

if (!interactive()) {
  stop("🚨 This script needs interactive mode for readline(). Run in RStudio/Positron!")
}

branch_name <- readline("🌿 Branch name: ")
package     <- readline("📦 Package name (default: junco): ")

if (nchar(trimws(package)) == 0L) package <- "junco"

package <- tolower(trimws(package))
branch_name <- trimws(branch_name)

if (nchar(branch_name) == 0L) {
  stop("🚨 Branch name cannot be empty!")
}

# Branch --- create feature branch (via shell template) -------

template_file <- if (is_windows) "check_feature.ps1" else "check_feature.sh"
template_ref <- sprintf("%s:dev/scripts/%s", dev_branch, template_file)

template_content <- tryCatch(
  run_git("show", template_ref),
  error = function(e) {
    stop(sprintf("🚨 Template not found in branch '%s': %s", dev_branch, template_ref))
  }
)

filled_script <- glue::glue(
  paste(template_content, collapse = "\n"),
  branch_name = branch_name,
  .open = "{{",
  .close = "}}"
)

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

message(sprintf("▶️  Creating branch '%s'...", branch_name))

result <- system2(shell_cmd, shell_args, stdout = TRUE, stderr = TRUE)
status <- attr(result, "status")
if (is.null(status)) status <- 0L
cat(result, sep = "\n")

if (status != 0L) {
  stop(sprintf("❌ Branch creation failed (exit %d).", status))
}

# DESCRIPTION --- update Remotes entry ------------------------

desc_path <- file.path(repo_root, "DESCRIPTION")
desc_lines <- readLines(desc_path)

pkg_pattern <- sprintf("(\\S+/%s)@\\S+", package)
match_idx <- grep(pkg_pattern, desc_lines, ignore.case = TRUE)

if (length(match_idx) == 0L) {
  stop(sprintf("🚨 Package '%s' not found in DESCRIPTION Remotes!", package))
}

old_line <- desc_lines[match_idx]
new_line <- sub(
  sprintf("(\\S+/%s)@\\S+", package),
  sprintf("\\1@%s", branch_name),
  old_line,
  ignore.case = TRUE
)

desc_lines[match_idx] <- new_line
writeLines(desc_lines, desc_path)

message(sprintf("📝 DESCRIPTION updated:\n   Old: %s\n   New: %s", trimws(old_line), trimws(new_line)))

# Push --- commit and push ------------------------------------

run_git("add", "DESCRIPTION")
run_git("commit", "-m", sprintf("'feat: test %s@%s'", package, branch_name))
run_git("push", "origin", branch_name)

message(sprintf("🚀 Pushed! Now go run the workflow on branch '%s'", branch_name))
message("🔗 https://github.com/vikram-rawat/scda.test/actions")
message("🎉 Feature branch ready!")

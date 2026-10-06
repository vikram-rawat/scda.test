$ErrorActionPreference = "Stop"

Set-Location (git rev-parse --show-toplevel)

$StashName = "sync-upstream-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "📡 Fetching {{upstream}}..."
git fetch {{upstream}}

Write-Host "📦 Stashing local changes as '$StashName'..."
git stash push --include-untracked -m $StashName 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "Nothing to stash." }

Write-Host "🔄 Resetting {{branch}} to {{upstream}}/{{branch}}..."
git checkout {{branch}}
git reset --hard {{upstream}}/{{branch}}

Write-Host "📦 Restoring local files..."
$StashRef = git stash list | Select-String $StashName | Select-Object -First 1
if ($StashRef) {
  $RefId = ($StashRef -split ":")[0]
  git checkout "stash@{0}" -- dev/ 2>$null
  git stash drop $RefId
  Write-Host "✅ dev/ restored!"
} else {
  Write-Host "ℹ️  Nothing to restore."
}

Write-Host "📝 Committing dev/ back..."
git add dev/
git commit -m "chore: preserve dev/ after upstream sync"

Write-Host "🚀 Pushing to origin..."
git push origin {{branch}} --force

Write-Host "✅ Done! {{branch}} synced with {{upstream}}/{{branch}}."

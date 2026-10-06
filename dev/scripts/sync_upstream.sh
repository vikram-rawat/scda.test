#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

STASH_NAME="sync-upstream-$(date +%s)"

echo "📡 Fetching {{upstream}}..."
git fetch {{upstream}}

echo "📦 Stashing local changes as '${STASH_NAME}'..."
git stash push --include-untracked -m "${STASH_NAME}" || true

echo "🔄 Resetting {{branch}} to {{upstream}}/{{branch}}..."
git checkout {{branch}}
git reset --hard {{upstream}}/{{branch}}

echo "📦 Restoring local files..."
STASH_REF=$(git stash list | grep "${STASH_NAME}" | head -1 | cut -d: -f1)
if [ -n "${STASH_REF}" ]; then
  git checkout "stash@{0}" -- dev/ 2>/dev/null || true
  git stash drop "${STASH_REF}"
  echo "✅ dev/ restored!"
else
  echo "ℹ️  Nothing to restore."
fi

echo "📝 Committing dev/ back..."
git add dev/
git commit -m "chore: preserve dev/ after upstream sync"

echo "🚀 Pushing to origin..."
git push origin {{branch}} --force

echo "✅ Done! {{branch}} synced with {{upstream}}/{{branch}}."

#!/bin/bash
# ============================================================
#  Pacific Ridgeway website — one-command deploy
#  Usage:  ./deploy.sh "optional commit message"
#  Pushes the current folder to GitHub (branch: main).
#  GitHub Pages then serves it live at the site domain.
# ============================================================
set -e
cd "$(dirname "$0")"

MSG="${1:-Update site $(date '+%Y-%m-%d %H:%M')}"

echo "→ Checking for changes…"
if [ -z "$(git status --porcelain)" ]; then
  echo "✓ Nothing to deploy — working tree is clean."
  exit 0
fi

echo "→ Changes to be deployed:"
git status --short

echo "→ Staging…"
git add -A

echo "→ Committing:  $MSG"
git commit -m "$MSG"

echo "→ Pushing to GitHub (origin/main)…"
git push origin main

echo ""
echo "✅ Deployed. GitHub Pages will rebuild in ~1 min."
echo "   Live: https://pacificridgeway.com  (and the github.io URL)"

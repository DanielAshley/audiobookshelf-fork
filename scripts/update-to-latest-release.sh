#!/bin/bash
#
# update-to-latest-release.sh
#
# Purpose: Update this fork's master branch to the latest *stable release tag*
#          from the original creator (advplyr), never to post-release master commits.
#
# This matches the "latest stable release only" workflow.
#
# Usage:
#   ./scripts/update-to-latest-release.sh           # interactive with confirmation
#   ./scripts/update-to-latest-release.sh --yes     # non-interactive (CI / automation)
#   ./scripts/update-to-latest-release.sh --dry-run # show what would happen
#
# Requirements:
#   - 'upstream' remote must point to the original creator (advplyr/audiobookshelf)
#   - SSH key configured (recommended per AGENTS.md)
#
# What it does:
#   1. Fetches all tags from upstream
#   2. Finds the highest semantic version tag (vX.Y.Z)
#   3. Stashes any local changes (including untracked)
#   4. Hard resets master to that tag
#   5. Force-pushes with lease to your fork (origin)
#   6. Restores your stashed changes
#
# Safety:
#   - Never pushes anything newer than a tagged release
#   - Uses --force-with-lease (safer than --force)
#   - Always stashes first

set -euo pipefail

DRY_RUN=false
YES=false
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --yes|-y)
            YES=true
            shift
            ;;
        --help|-h)
            sed -n '2,30p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage." >&2
            exit 1
            ;;
    esac
done

cd "$REPO_ROOT"

# --- Safety checks ---
if ! git remote get-url upstream >/dev/null 2>&1; then
    echo "ERROR: 'upstream' remote is not configured."
    echo "Run this first:"
    echo "  git remote add upstream git@github.com:advplyr/audiobookshelf.git"
    exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
    echo "ERROR: 'origin' remote is not configured."
    exit 1
fi

CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "master" && "$CURRENT_BRANCH" != "main" ]]; then
    echo "WARNING: You are on branch '$CURRENT_BRANCH', not master/main."
    if [[ "$YES" != true ]]; then
        read -rp "Continue anyway? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] || exit 1
    fi
fi

echo "==> Fetching latest tags from original creator (upstream)..."
if [[ "$DRY_RUN" == true ]]; then
    echo "   (dry-run: would run 'git fetch upstream --tags --prune')"
else
    git fetch upstream --tags --prune --quiet
fi

# Find the latest stable release tag (vX.Y.Z, sorted by version)
LATEST_TAG=$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1)

if [[ -z "$LATEST_TAG" ]]; then
    echo "ERROR: No version tags found from upstream."
    exit 1
fi

CURRENT_DESCRIBE=$(git describe --tags --always 2>/dev/null || echo "unknown")

echo ""
echo "Current state:           $CURRENT_DESCRIBE"
echo "Latest stable release:   $LATEST_TAG"
echo ""

if git merge-base --is-ancestor "$LATEST_TAG" HEAD 2>/dev/null; then
    echo "✓ Your branch is already at or beyond the latest release tag."
    echo "  Nothing to do."
    exit 0
fi

echo "This will:"
echo "  • Stash any uncommitted work (including untracked files)"
echo "  • Hard reset 'master' to $LATEST_TAG"
echo "  • Force-push (with lease) to your fork (origin/master)"
echo "  • Restore your stashed work"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "==> DRY RUN - no changes will be made"
    echo "Would reset to tag: $LATEST_TAG"
    echo "Would push to:      $(git remote get-url origin)"
    exit 0
fi

if [[ "$YES" != true ]]; then
    read -rp "Proceed with update to $LATEST_TAG? [y/N] " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo "==> Stashing local changes..."
STASH_NAME="update-to-release-$(date +%s)"
if git stash push -u -m "$STASH_NAME" --quiet; then
    STASHED=true
else
    STASHED=false
fi

echo "==> Checking out master and resetting to $LATEST_TAG..."
git checkout -q master
git reset --hard "$LATEST_TAG"

echo "==> Pushing to your fork (origin) via SSH..."
git push --force-with-lease origin master

if [[ "$STASHED" == true ]]; then
    echo "==> Restoring your stashed changes..."
    git stash pop --quiet || echo "Note: Stash pop had conflicts or issues. Your changes are in the stash."
fi

echo ""
echo "✅ Done. Your master branch is now at the latest stable release: $LATEST_TAG"
echo ""
echo "To do this again in the future, just run:"
echo "  ./scripts/update-to-latest-release.sh"
echo ""

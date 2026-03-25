#!/usr/bin/env sh
set -eu

# check required environment variables
: "${BUILD_DIR:?BUILD_DIR is required (call via make publish_orphan)}"
: "${PUBLISH_BRANCH:?PUBLISH_BRANCH is required}"
: "${GIT_AUTHOR_NAME:?GIT_AUTHOR_NAME is required}"
: "${GIT_AUTHOR_EMAIL:?GIT_AUTHOR_EMAIL is required}"
: "${PUBLISH_COMMIT_MESSAGE:?PUBLISH_COMMIT_MESSAGE is required}"

# safety checks
test -d .git || { echo "ERROR: .git not found. Run publish_orphan in the repo root." >&2; exit 2; }
test -d "$BUILD_DIR" || { echo "ERROR: BUILD_DIR '$BUILD_DIR' not found" >&2; exit 2; }
test "$BUILD_DIR" != "." || { echo "ERROR: BUILD_DIR must not be '.'" >&2; exit 2; }
test "$BUILD_DIR" != "/" || { echo "ERROR: BUILD_DIR must not be '/'" >&2; exit 2; }

# clean-up working copy
git reset --hard
git clean -fd

# checkout (new) orphan branch
git branch -D "$PUBLISH_BRANCH" 2>/dev/null || true
git switch --orphan "$PUBLISH_BRANCH"
git rm -r --cached . 2>/dev/null || true

# delete any old files and move build content
find . -mindepth 1 -maxdepth 1 ! -name '.git' ! -name "$BUILD_DIR" -exec rm -rf {} +
mv "$BUILD_DIR"/* .
rm -rf "$BUILD_DIR"

# commit and push
git add -f .
if git diff --cached --quiet; then
  echo "no changes to publish"
else
  git -c user.name="$GIT_AUTHOR_NAME" -c user.email="$GIT_AUTHOR_EMAIL" commit -m "$PUBLISH_COMMIT_MESSAGE"
  git push --force origin "$PUBLISH_BRANCH"
fi

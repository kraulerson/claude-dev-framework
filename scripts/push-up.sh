#!/usr/bin/env bash
# push-up.sh — Promote a project-specific rule/hook to the global framework
set -euo pipefail

FRAMEWORK_CLONE="$HOME/.claude-dev-framework"

if [ $# -lt 2 ]; then
  echo "Usage: push-up.sh <file-path> --global | --project-template" >&2; exit 1
fi

FILE_PATH="$1"; MODE="$2"
if [ ! -f "$FILE_PATH" ]; then
  echo "ERROR: File not found: $FILE_PATH" >&2; exit 1
fi

echo "=== Push-Up: Promote to Global Framework ==="
echo "File: $FILE_PATH"
echo "Mode: $MODE"
echo ""
echo "--- File Content ---"
cat "$FILE_PATH"
echo ""
echo "--- End Content ---"
echo ""
read -rp "Proceed? (y/n): " confirm
[ "$confirm" != "y" ] && { echo "Aborted."; exit 0; }

BASENAME=$(basename "$FILE_PATH")
DATE=$(date +%Y%m%d)

pushd "$FRAMEWORK_CLONE" > /dev/null
BRANCH_NAME="push-up/${BASENAME%.*}-${DATE}"
git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"

case "$MODE" in
  --global)
    case "$BASENAME" in
      *.sh) DEST="hooks/$BASENAME" ;;
      *.md) DEST="rules/$BASENAME" ;;
      *.yml|*.yaml) DEST="profiles/$BASENAME" ;;
      *) DEST="rules/$BASENAME" ;;
    esac
    ;;
  --project-template)
    DEST="templates/project-examples/$BASENAME"
    ;;
  *)
    echo "ERROR: Mode must be --global or --project-template" >&2; exit 1 ;;
esac

cp "$OLDPWD/$FILE_PATH" "$DEST"
git add "$DEST"
git commit -m "Add $BASENAME from project (push-up)"

echo ""
read -rp "Push branch and create PR? (y/n): " push_choice
if [ "$push_choice" = "y" ]; then
  git push -u origin "$BRANCH_NAME"
  if command -v gh &>/dev/null; then
    gh pr create --title "Push-up: $BASENAME" --body "Promoted from project via push-up.sh ($MODE)"
  fi
fi

git checkout main
popd > /dev/null
echo "Done."

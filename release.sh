#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIND="${1:-patch}"
MESSAGE="${2:-Обновление Invis}"
VERSION_FILE="$PROJECT_DIR/VERSION"
CURRENT="$(<"$VERSION_FILE")"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "$KIND" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    *) print -u2 "Использование: ./release.sh [patch|minor|major] [описание изменений]"; exit 2 ;;
esac
NEXT="$MAJOR.$MINOR.$PATCH"
TAG="v$NEXT"
ARCHIVE="$PROJECT_DIR/dist/Invis-$NEXT-macOS.zip"

print -r -- "$NEXT" > "$VERSION_FILE"
"$PROJECT_DIR/build-app.sh"
mkdir -p "$PROJECT_DIR/dist"
ditto -c -k --sequesterRsrc --keepParent "$HOME/Applications/Invis.app" "$ARCHIVE"

cd "$PROJECT_DIR"
git add -A -- .gitignore Package.swift README.md VERSION build-app.sh release.sh Sources
git commit -m "release: $TAG — $MESSAGE"
git tag -a "$TAG" -m "Invis $TAG"
git push origin HEAD "$TAG"
gh release create "$TAG" "$ARCHIVE" --title "Invis $TAG" --notes "$MESSAGE"

print -r -- "Готов релиз $TAG: $ARCHIVE"

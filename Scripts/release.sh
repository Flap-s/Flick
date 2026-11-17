#!/bin/zsh
# Publishes a new Flick version on GitHub Releases, where the app's updater finds it.
# Usage: Scripts/release.sh 1.1.0 "Ce qui change"
set -euo pipefail

cd "$(dirname "$0")/.."
NEW="${1:?usage: Scripts/release.sh X.Y.Z \"notes de version\"}"
NOTES="${2:-Flick $NEW}"

[[ "$NEW" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "La version doit ressembler à 1.2.3"; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { echo "Ajoutez d'abord le dépôt GitHub : git remote add origin …"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commitez ou mettez de côté vos changements d'abord."; exit 1; }
if git rev-parse "v$NEW" >/dev/null 2>&1; then echo "Le tag v$NEW existe déjà."; exit 1; fi

echo "$NEW" > VERSION
swift test
./Scripts/build-app.sh
# build-app.sh signs outside iCloud and zips that clean copy into build.noindex/Flick.zip.

if ! git diff --quiet VERSION; then
  git add VERSION
  git commit -m "Release $NEW"
fi
git tag "v$NEW"
git push origin HEAD "v$NEW"
gh release create "v$NEW" build.noindex/Flick.dmg build.noindex/Flick.zip --title "Flick $NEW" --notes "$NOTES"
echo "Flick $NEW publiée"

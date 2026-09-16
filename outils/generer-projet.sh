#!/bin/zsh
# Régénère Seance.xcodeproj à partir de project.yml.
# XcodeGen est téléchargé une fois dans outils/.bin (pas de Homebrew sur ce Mac).
set -euo pipefail
racine=${0:A:h:h}
version=2.46.0
binaire="$racine/outils/.bin/xcodegen/bin/xcodegen"

if [[ ! -x $binaire ]] || [[ $("$binaire" --version 2>/dev/null) != *$version* ]]; then
  echo "Téléchargement de XcodeGen $version…"
  temporaire=$(mktemp -d)
  curl -fsSL "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip" -o "$temporaire/xcodegen.zip"
  rm -rf "$racine/outils/.bin/xcodegen"
  mkdir -p "$racine/outils/.bin"
  unzip -q "$temporaire/xcodegen.zip" -d "$racine/outils/.bin"
  rm -rf "$temporaire"
fi

"$binaire" generate --spec "$racine/project.yml" --project "$racine"

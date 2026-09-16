#!/bin/zsh
# Lance les tests de SeanceKit avec les Command Line Tools.
# Ils suffisent pour ce paquet (pas de SwiftData) et n'exigent pas la licence Xcode.
# Le plugin de macros de Swift Testing y est rangé dans un sous-dossier qu'il faut indiquer.
set -euo pipefail
racine=${0:A:h:h}
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
exec swift test --package-path "$racine/SeanceKit" \
  -Xswiftc -plugin-path -Xswiftc "$DEVELOPER_DIR/usr/lib/swift/host/plugins/testing" "$@"

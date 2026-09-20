#!/bin/zsh
# Tout vérifier avant un commit : les tests de SeanceKit et de SeanceDonnees, puis les tests d'interface sur le
# simulateur d'iPhone et ceux de l'iPad. Dix à quinze minutes. S'arrête au premier échec.
#
#   outils/verifier.sh            # tout
#   outils/verifier.sh --rapide   # sans les tests d'interface (une minute)
set -uo pipefail
racine=${0:A:h:h}
etape() { print -P "%B── $1%b"; }

etape "SeanceKit"
(cd "$racine/SeanceKit" && swift test 2>&1 | grep -E "Test run with|✘|error:" | tail -5; exit ${pipestatus[1]}) || { echo "Échec : SeanceKit."; exit 1; }

etape "SeanceDonnees"
(cd "$racine/SeanceDonnees" && xcodebuild test -scheme SeanceDonnees -destination 'platform=macOS' 2>&1 \
  | grep -E "Test run with|✘|error:|\*\* TEST" | tail -5; exit ${pipestatus[1]}) || { echo "Échec : SeanceDonnees."; exit 1; }

[[ ${1:-} == --rapide ]] && { echo "Vérification rapide : tout passe."; exit 0; }

etape "Interface, iPhone"
"$racine/outils/tests-interface.sh" || { echo "Échec : interface iPhone (journal : .build/tests-interface.log)."; exit 1; }

etape "Interface, iPad"
# Après plusieurs séries de tests, le simulateur d'iPad ne pivote plus et le test du paysage échoue à tort : on le redémarre.
ipad=$(xcrun simctl list devices available | grep -F "    iPad Air 11-inch (M3) (" | head -1 | grep -o -E '[0-9A-F]{8}-[0-9A-F-]{27}')
[[ -n $ipad ]] && { xcrun simctl shutdown $ipad > /dev/null 2>&1; xcrun simctl boot $ipad > /dev/null 2>&1; }
SIMULATEUR="iPad Air 11-inch (M3)" RESULTAT="$racine/.build/ipad.xcresult" "$racine/outils/tests-interface.sh" IPadTests \
  || { echo "Échec : interface iPad."; exit 1; }
# Un test sauté (mauvais simulateur) n'a rien vérifié : ce n'est pas une réussite.
grep -q "Test Case .* skipped" "$racine/.build/tests-interface.log" && { echo "Échec : tests iPad sautés, rien n'a été vérifié."; exit 1; }

echo "Tout passe."

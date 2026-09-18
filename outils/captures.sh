#!/bin/zsh
# Captures d'écran automatiques de l'app sur le simulateur iPhone, avec de vraies fiches TMDB : de quoi vérifier
# l'interface iPhone sans l'avoir en main. La clé TMDB se lit dans outils/.cle-tmdb (une ligne, ignorée par git).
#
#   echo "ma-clé-tmdb" > outils/.cle-tmdb
#   outils/captures.sh                 # toutes les visites
#   outils/captures.sh testStatistiques  # une seule
set -euo pipefail
racine=${0:A:h:h}
cle="$racine/outils/.cle-tmdb"
[[ -s $cle ]] || { echo "Écris ta clé TMDB dans outils/.cle-tmdb (fichier ignoré par git), puis relance."; exit 1; }
simulateur=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Pro \(/ { print $2; exit }')
[[ -n $simulateur ]] || { echo "Simulateur iPhone 17 Pro introuvable."; exit 1; }
sortie="$racine/.build/captures"
rm -rf "$sortie" "$racine/.build/captures.xcresult"
"$racine/outils/generer-projet.sh" > /dev/null
essais=(-only-testing:SeanceUITests/VisiteTests)
[[ -n ${1:-} ]] && essais=(-only-testing:SeanceUITests/VisiteTests/$1)
TEST_RUNNER_SEANCE_CLE_TMDB=$(<"$cle") xcodebuild test -project "$racine/Seance.xcodeproj" -scheme Seance \
  -destination "id=$simulateur" -derivedDataPath "$racine/.build/dd-captures" \
  -resultBundlePath "$racine/.build/captures.xcresult" $essais 2>&1 | grep -E 'passed \(|failed \(|error:' || true
mkdir -p "$sortie"
xcrun xcresulttool export attachments --path "$racine/.build/captures.xcresult" --output-path "$sortie" > /dev/null
echo "Captures dans $sortie ($(ls "$sortie" | grep -c png) images)."

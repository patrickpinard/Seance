#!/bin/zsh
# Captures d'écran automatiques de l'app sur le simulateur iPhone : de quoi vérifier l'interface iPhone sans l'avoir
# en main. Sans clé, un faux TMDB rejoue des réponses enregistrées ; avec une clé dans outils/.cle-tmdb (une ligne,
# ignorée par git), les visites se font sur le vrai TMDB.
#
#   outils/captures.sh                   # le tour complet, sans clé
#   echo "ma-clé-tmdb" > outils/.cle-tmdb
#   outils/captures.sh                   # toutes les visites, vrai TMDB
#   outils/captures.sh testStatistiques  # une seule
set -euo pipefail
racine=${0:A:h:h}
cle="$racine/outils/.cle-tmdb"
simulateur=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Pro \(/ { print $2; exit }')
[[ -n $simulateur ]] || { echo "Simulateur iPhone 17 Pro introuvable."; exit 1; }
sortie="$racine/.build/captures"
rm -rf "$sortie" "$racine/.build/captures.xcresult"
"$racine/outils/generer-projet.sh" > /dev/null
# Sans clé : le tour complet avec le faux TMDB (réponses enregistrées, toujours les mêmes images).
# Avec une clé dans outils/.cle-tmdb : les visites sur le vrai TMDB.
if [[ -s $cle ]]; then
  essais=(-only-testing:SeanceUITests/VisiteTests)
  [[ -n ${1:-} ]] && essais=(-only-testing:SeanceUITests/VisiteTests/$1)
  export TEST_RUNNER_SEANCE_CLE_TMDB=$(<"$cle")
else
  essais=(-only-testing:SeanceUITests/TourCompletTests -only-testing:SeanceUITests/ProgrammeTeleTests -only-testing:SeanceUITests/ReglagesTests)
fi
# Un simulateur qui démarre pendant le test le laisse parfois sur l'écran d'accueil : on l'attend d'abord.
xcrun simctl bootstatus "$simulateur" -b > /dev/null 2>&1 || true
xcodebuild test -project "$racine/Seance.xcodeproj" -scheme Seance \
  -destination "id=$simulateur" -derivedDataPath "$racine/.build/dd-captures" \
  -resultBundlePath "$racine/.build/captures.xcresult" $essais 2>&1 | grep -E 'passed \(|failed \(|error:' || true
mkdir -p "$sortie"
xcrun xcresulttool export attachments --path "$racine/.build/captures.xcresult" --output-path "$sortie" > /dev/null
echo "Captures dans $sortie ($(ls "$sortie" | grep -c png) images)."

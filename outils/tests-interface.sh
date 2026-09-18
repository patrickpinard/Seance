#!/bin/zsh
# Lance des tests d'interface sur le simulateur iPhone 17 Pro, en relançant une fois si le simulateur reste figé sur son
# écran d'accueil (cela arrive au premier lancement après une recompilation : le test ne démarre jamais).
#
#   outils/tests-interface.sh                                   # tous les tests sans clé TMDB
#   outils/tests-interface.sh TourCompletTests/testGrandTexte   # un seul
#   RESULTAT=.build/x.xcresult outils/tests-interface.sh …      # où ranger le résultat
set -uo pipefail
racine=${0:A:h:h}
simulateur=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Pro \(/ { print $2; exit }')
[[ -n $simulateur ]] || { echo "Simulateur iPhone 17 Pro introuvable."; exit 1; }
resultat=${RESULTAT:-$racine/.build/tests-interface.xcresult}
journal="$racine/.build/tests-interface.log"
if (( $# )); then
  essais=(); for nom in "$@"; do essais+=(-only-testing:SeanceUITests/$nom); done
else
  essais=(-only-testing:SeanceUITests/TourCompletTests -only-testing:SeanceUITests/ProgrammeTeleTests
          -only-testing:SeanceUITests/ReglagesTests -only-testing:SeanceUITests/SynchroTests)
fi
"$racine/outils/generer-projet.sh" > /dev/null

lancer() {
  rm -rf "$resultat"
  xcrun simctl bootstatus "$simulateur" -b > /dev/null 2>&1 || true
  xcodebuild test -project "$racine/Seance.xcodeproj" -scheme Seance -destination "id=$simulateur" \
    -derivedDataPath "$racine/.build/dd-captures" -resultBundlePath "$resultat" $essais \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 400 -maximum-test-execution-time-allowance 480 \
    > "$journal" 2>&1 &
  local pid=$!
  # Compilé et lancé, un test écrit « Test Case … started » en moins de quatre minutes ; sinon, le simulateur est figé.
  local attendu=0
  while kill -0 $pid 2> /dev/null; do
    if grep -q "Test Case .* started" "$journal" 2> /dev/null; then wait $pid; return $?; fi
    (( attendu += 5 )); sleep 5
    if (( attendu > 360 )); then kill $pid 2> /dev/null; wait $pid 2> /dev/null; return 99; fi
  done
  wait $pid
}

lancer; code=$?
if (( code == 99 )); then
  echo "Simulateur figé : on l'éteint, et on recommence une fois."
  xcrun simctl shutdown "$simulateur" > /dev/null 2>&1 || true
  lancer; code=$?
fi
grep -E "Test Case .*(passed|failed)|error:" "$journal" | cut -c1-260
exit $code

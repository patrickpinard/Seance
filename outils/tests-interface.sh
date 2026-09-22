#!/bin/zsh
# Lance des tests d'interface sur un simulateur (iPhone 17 Pro d'office), en relançant une fois si le simulateur reste figé sur son
# écran d'accueil (cela arrive au premier lancement après une recompilation : le test ne démarre jamais).
#
#   outils/tests-interface.sh                                   # tous les tests sans clé TMDB
#   outils/tests-interface.sh TourCompletTests/testGrandTexte   # un seul
#   RESULTAT=.build/x.xcresult outils/tests-interface.sh …      # où ranger le résultat
#   SIMULATEUR="iPad Air 11-inch (M4)" outils/tests-interface.sh IPadTests   # sur un autre simulateur
set -uo pipefail
racine=${0:A:h:h}
modele=${SIMULATEUR:-iPhone 17 Pro}
simulateur=$(xcrun simctl list devices available | grep -F "    $modele (" | tail -1 | grep -o -E '[0-9A-F]{8}-[0-9A-F-]{27}')
[[ -n $simulateur ]] || { echo "Simulateur « $modele » introuvable."; exit 1; }
resultat=${RESULTAT:-$racine/.build/tests-interface.xcresult}
journal="$racine/.build/tests-interface.log"
if (( $# )); then
  essais=(); for nom in "$@"; do essais+=(-only-testing:SeanceUITests/$nom); done
else
  essais=(-only-testing:SeanceUITests/TourCompletTests -only-testing:SeanceUITests/ProgrammeTeleTests
          -only-testing:SeanceUITests/ReglagesTests -only-testing:SeanceUITests/SynchroTests
          -only-testing:SeanceUITests/EtatsVidesTests -only-testing:SeanceUITests/AccessibiliteTests -only-testing:SeanceUITests/ParcoursSoireeTests -only-testing:SeanceUITests/FamilleTests -only-testing:SeanceUITests/LectureTests
          -only-testing:SeanceUITests/VideosPersoTests)
fi
"$racine/outils/generer-projet.sh" > /dev/null

# Attend la fin de xcodebuild. Après un test en échec, il lui arrive de rester pendu une fois le bilan écrit
# (« Test Suite 'Selected tests' … ») : on lui laisse deux minutes pour ranger le résultat, puis on l'arrête.
finir() {
  local pid=$1 depuis=0
  while kill -0 $pid 2> /dev/null; do
    sleep 5
    if grep -E -q "Test Suite 'Selected tests' (passed|failed)" "$journal" 2> /dev/null; then
      (( depuis += 5 ))
      if (( depuis > 120 )); then
        kill -INT $pid 2> /dev/null; sleep 10; kill -KILL $pid 2> /dev/null
        wait $pid 2> /dev/null
        grep -q "Test Suite 'Selected tests' passed" "$journal" && return 0 || return 65
      fi
    fi
  done
  wait $pid
}

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
    if grep -q "Test Case .* started" "$journal" 2> /dev/null; then finir $pid; return $?; fi
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
grep -E "Test Case .*(passed|failed|skipped)|error:" "$journal" | cut -c1-260
exit $code

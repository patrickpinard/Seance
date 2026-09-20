#!/bin/zsh
# Le transfert de configuration, de bout en bout entre deux simulateurs : une Apple TV vide affiche le code 424242,
# l'iPhone de démonstration lui envoie tout, et la TV doit montrer les listes reçues (.build/captures-tv/envoi-*.png).
set -uo pipefail
racine=${0:A:h:h}
tv=$(xcrun simctl list devices available | grep -F "Apple TV 4K (3rd generation) (" | grep -v 1080p | tail -1 | grep -o -E '[0-9A-F]{8}-[0-9A-F-]{27}')
[[ -n $tv ]] || { echo "Simulateur d'Apple TV introuvable."; exit 1; }
"$racine/outils/generer-projet.sh" > /dev/null
xcodebuild build -project "$racine/Seance.xcodeproj" -scheme SeanceTV -destination "platform=tvOS Simulator,id=$tv" \
  -derivedDataPath "$racine/.build/dd-tv" > "$racine/.build/test-envoi-tv.log" 2>&1 || { echo "Compilation de l'app TV en échec."; exit 1; }
xcrun simctl boot "$tv" 2> /dev/null; xcrun simctl bootstatus "$tv" -b > /dev/null 2>&1
xcrun simctl install "$tv" "$racine/.build/dd-tv/Build/Products/Debug-appletvsimulator/SeanceTV.app"
xcrun simctl terminate "$tv" ch.patrick.seance.tv > /dev/null 2>&1
SIMCTL_CHILD_SEANCE_DEMO=vide SIMCTL_CHILD_SEANCE_FAUX_TMDB="$racine/SeanceKit/Tests/SeanceKitTests/Fixtures" \
  SIMCTL_CHILD_SEANCE_TV_CONFIGURER=1 SIMCTL_CHILD_SEANCE_TV_CODE=424242 xcrun simctl launch "$tv" ch.patrick.seance.tv > /dev/null
sleep 6; mkdir -p "$racine/.build/captures-tv"
xcrun simctl io "$tv" screenshot "$racine/.build/captures-tv/envoi-1-code.png" > /dev/null 2>&1
TEST_RUNNER_SEANCE_TV_ATTENDUE=1 RESULTAT="$racine/.build/envoi-tv.xcresult" "$racine/outils/tests-interface.sh" EnvoiAppleTVTests; code=$?
sleep 3
xcrun simctl io "$tv" screenshot "$racine/.build/captures-tv/envoi-2-recu.png" > /dev/null 2>&1
exit $code

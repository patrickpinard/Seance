#!/bin/zsh
# Captures de Séance sur Apple TV, dans le simulateur, avec les données de démonstration et le faux TMDB :
# un lancement par écran (voir DepartTV), une image 3840 × 2160 par écran dans .build/captures-tv/.
#
#   outils/captures-tv.sh
set -uo pipefail
racine=${0:A:h:h}
simulateur=$(xcrun simctl list devices available | grep -F "Apple TV 4K (3rd generation) (" | grep -v 1080p | tail -1 | grep -o -E '[0-9A-F]{8}-[0-9A-F-]{27}')
[[ -n $simulateur ]] || { echo "Simulateur d'Apple TV 4K introuvable."; exit 1; }
sortie="$racine/.build/captures-tv"; mkdir -p "$sortie"
"$racine/outils/generer-projet.sh" > /dev/null
xcodebuild build -project "$racine/Seance.xcodeproj" -scheme SeanceTV -destination "platform=tvOS Simulator,id=$simulateur" \
  -derivedDataPath "$racine/.build/dd-tv" > "$racine/.build/captures-tv.log" 2>&1 || { echo "La compilation a échoué : .build/captures-tv.log"; exit 1; }
xcrun simctl boot "$simulateur" 2> /dev/null; xcrun simctl bootstatus "$simulateur" -b > /dev/null 2>&1
xcrun simctl install "$simulateur" "$racine/.build/dd-tv/Build/Products/Debug-appletvsimulator/SeanceTV.app"

capturer() {  # nom, puis variables d'environnement « CLE=valeur »
  local nom=$1; shift
  xcrun simctl terminate "$simulateur" ch.patrick.seance.tv > /dev/null 2>&1
  local -a env=(SIMCTL_CHILD_SEANCE_DEMO=1 "SIMCTL_CHILD_SEANCE_FAUX_TMDB=$racine/SeanceKit/Tests/SeanceKitTests/Fixtures")
  for v in "$@"; do env+=("SIMCTL_CHILD_$v"); done
  env "${env[@]}" xcrun simctl launch "$simulateur" ch.patrick.seance.tv > /dev/null
  sleep 9
  xcrun simctl io "$simulateur" screenshot "$sortie/$nom.png" > /dev/null 2>&1 && echo "$nom.png"
}
capturer tv-accueil
capturer tv-cesoir SEANCE_TV_ONGLET=ceSoir
capturer tv-listes SEANCE_TV_ONGLET=listes
capturer tv-tele SEANCE_TV_ONGLET=tele
capturer tv-explorer SEANCE_TV_ONGLET=explorer
capturer tv-profil SEANCE_TV_ONGLET=profil
capturer tv-nas SEANCE_TV_ONGLET=nas
capturer tv-reglages SEANCE_TV_ONGLET=reglages
capturer tv-fiche SEANCE_TV_FICHE=film:324552
capturer tv-fiche-serie SEANCE_TV_FICHE=serie:108978

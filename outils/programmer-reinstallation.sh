#!/bin/zsh
# Programme la réinstallation automatique de Séance sur ce Mac (8.11) : un agent de launchd lance
# outils/reinstallation-auto.sh toutes les deux heures, tant que la session est ouverte.
#
#   outils/programmer-reinstallation.sh            # programmer (ou reprogrammer)
#   outils/programmer-reinstallation.sh --arreter  # ne plus réinstaller automatiquement
#
# Journal : ~/Library/Logs/Seance-reinstallation.log
set -euo pipefail
racine=${0:A:h:h}
etiquette=ch.patrick.seance.reinstallation
agent="$HOME/Library/LaunchAgents/$etiquette.plist"
domaine="gui/$(id -u)"

launchctl bootout "$domaine/$etiquette" 2> /dev/null || true
if [[ ${1:-} == --arreter ]]; then
  rm -f "$agent"
  echo "Réinstallation automatique arrêtée."
  exit 0
fi

mkdir -p "${agent:h}"
cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$etiquette</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$racine/outils/reinstallation-auto.sh</string></array>
  <key>StartInterval</key><integer>7200</integer>
  <key>RunAtLoad</key><false/>
  <key>ProcessType</key><string>Background</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string></dict>
</dict>
</plist>
PLIST
launchctl bootstrap "$domaine" "$agent"
echo "Réinstallation automatique programmée : toutes les deux heures, pour les appareils installés il y a plus de 4 jours."
echo "Journal : ~/Library/Logs/Seance-reinstallation.log"

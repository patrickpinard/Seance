#!/bin/zsh
# Compile Séance en Release et l'installe sur les iPhone et iPad branchés et sur ce Mac.
# Avec un compte Apple gratuit, l'app cesse de s'ouvrir au bout de 7 jours : relancer ce script suffit,
# les données restent sur chaque appareil.
#
#   outils/installer.sh            # iPhone, iPad et Mac
#   outils/installer.sh --iphone   # iPhone seulement
#   outils/installer.sh --ipad     # iPad seulement
#   outils/installer.sh --mac      # Mac seulement
#
# Un iPhone ou un iPad doit être jumelé avec ce Mac, sous iOS ou iPadOS 26, et avoir le mode développeur activé
# (Réglages › Confidentialité et sécurité › Mode développeur).
set -euo pipefail
racine=${0:A:h:h}
projet="$racine/Seance.xcodeproj"
derives="$racine/.build/installation"
journal="$racine/.build/installation.log"
application="/Applications/Séance.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

iphone=true
ipad=true
mac=true
case "${1:-}" in
  --iphone) mac=false; ipad=false ;;
  --ipad) mac=false; iphone=false ;;
  --mac) iphone=false; ipad=false ;;
  "") ;;
  *) echo "Option inconnue : $1 (--iphone, --ipad ou --mac)"; exit 2 ;;
esac

mkdir -p "$racine/.build"
"$racine/outils/generer-projet.sh" > /dev/null

xcode() {
  local destination=$1 nom=$2; shift 2
  if ! xcodebuild -project "$projet" -scheme Seance -configuration Release -destination "$destination" \
      -derivedDataPath "$derives" -allowProvisioningUpdates "$@" > "$journal" 2>&1; then
    grep -E 'error:' "$journal" | sort -u | head -20
    echo "La compilation pour $nom a échoué. Journal complet : $journal"
    exit 1
  fi
}

# Compile, puis vérifie la signature du produit. Une compilation incrémentale réécrit parfois les métadonnées
# App Intents du widget après sa signature (« a sealed resource is missing or invalid ») : tout est alors recompilé.
compiler() {
  local destination=$1 nom=$2 app=$3
  echo "Compilation pour $nom…"
  xcode "$destination" "$nom" build
  if ! codesign --verify --deep --strict "$app" 2> /dev/null; then
    echo "Signature incohérente après une compilation incrémentale : recompilation complète pour $nom…"
    xcode "$destination" "$nom" clean build
    codesign --verify --deep --strict "$app"
  fi
}

version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1"
}

# Les appareils physiques branchés et jumelés : « identifiant<TAB>modèle », l'identifiant précédant « (UDID) ».
appareils() {
  # « connected » quand un tunnel est déjà ouvert ; l'espace écarte « unavailable ».
  xcrun devicectl list devices 2>/dev/null | awk '/physical/ && / (available|connected)/ {
    for (i = 1; i < NF; i++) if ($(i+1) == "(UDID)") { id = $i }
    modele = ($0 ~ /iPad/) ? "iPad" : "iPhone"
    print id "\t" modele
  }'
}

installer_sur() {
  local udid=$1 nom=$2
  local app="$derives/Build/Products/Release-iphoneos/Seance.app"
  # Compiler pour cet appareil l'inscrit au profil d'installation du compte gratuit.
  compiler "id=$udid" "$nom" "$app"
  if ! xcrun devicectl device install app --device "$udid" "$app" > "$journal.installation" 2>&1; then
    grep -i -E "error|developer mode|minimum|version" "$journal.installation" | head -5
    echo "${nom#l\'} : l'installation a échoué. Vérifie qu'il est déverrouillé, sous iOS ou iPadOS 26, mode développeur activé."
    return 1
  fi
  echo "${nom#l\'} : Séance $(version "$app/Info.plist") installée."
}

if $iphone || $ipad; then
  trouve=false
  while IFS=$'\t' read -r udid modele; do
    [[ -z $udid ]] && continue
    if [[ $modele == iPad ]]; then $ipad || continue; nom="l'iPad"; else $iphone || continue; nom="l'iPhone"; fi
    trouve=true
    installer_sur "$udid" "$nom" || $mac || exit 1
  done < <(appareils)
  if ! $trouve; then
    echo "Aucun iPhone ni iPad disponible : branche-le, déverrouille-le, active son mode développeur, puis relance."
    $mac || exit 1
  fi
fi

if $mac; then
  app="$derives/Build/Products/Release-maccatalyst/Seance.app"
  compiler "platform=macOS,variant=Mac Catalyst" "le Mac" "$app"
  ouverte=false
  if pgrep -x Seance > /dev/null; then
    ouverte=true
    # Une feuille ouverte (filtres, bande-annonce) fait refuser la fermeture : rien n'est remplacé dans ce cas.
    osascript -e 'quit app id "ch.patrick.seance"' > /dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -x Seance > /dev/null || break; sleep 0.5; done
    if pgrep -x Seance > /dev/null; then
      echo "Séance est occupée sur le Mac (une feuille ou une fenêtre est ouverte) : ferme-la, puis relance outils/installer.sh --mac."
      exit 1
    fi
  fi
  rm -rf "$application"
  ditto "$app" "$application"
  codesign --verify --deep --strict "$application"
  # Sans ce réenregistrement, macOS garde l'ancienne copie en mémoire et refuse parfois d'ouvrir la nouvelle.
  "$lsregister" -f "$application"
  echo "Mac : Séance $(version "$application/Contents/Info.plist") installée dans /Applications."
  if $ouverte; then open "$application"; fi
fi

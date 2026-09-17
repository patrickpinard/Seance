#!/bin/zsh
# Compile Séance en Release et l'installe sur l'iPhone branché et sur ce Mac.
# Avec un compte Apple gratuit, l'app cesse de s'ouvrir au bout de 7 jours : relancer ce script suffit,
# les données restent sur chaque appareil.
#
#   outils/installer.sh            # iPhone et Mac
#   outils/installer.sh --iphone   # iPhone seulement
#   outils/installer.sh --mac      # Mac seulement
set -euo pipefail
racine=${0:A:h:h}
projet="$racine/Seance.xcodeproj"
derives="$racine/.build/installation"
journal="$racine/.build/installation.log"
application="/Applications/Séance.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

iphone=true
mac=true
case "${1:-}" in
  --iphone) mac=false ;;
  --mac) iphone=false ;;
  "") ;;
  *) echo "Option inconnue : $1 (--iphone ou --mac)"; exit 2 ;;
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

if $iphone; then
  # L'iPhone physique connecté et jumelé ; son identifiant précède « (UDID) ».
  udid=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /available/ { for (i = 1; i < NF; i++) if ($(i+1) == "(UDID)") { print $i; exit } }')
  if [[ -z $udid ]]; then
    echo "Aucun iPhone disponible : branche-le, déverrouille-le, puis relance (ou utilise --mac)."
    $mac || exit 1
    iphone=false
  else
    app="$derives/Build/Products/Release-iphoneos/Seance.app"
    compiler "id=$udid" "l'iPhone" "$app"
    xcrun devicectl device install app --device "$udid" "$app" > /dev/null
    echo "iPhone : Séance $(version "$app/Info.plist") installée."
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

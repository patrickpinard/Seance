#!/bin/zsh
# Compile Séance en Release et l'installe sur les iPhone et iPad branchés, sur l'Apple TV jumelée et sur ce Mac.
# Avec un compte Apple gratuit, l'app cesse de s'ouvrir au bout de 7 jours : relancer ce script suffit,
# les données restent sur chaque appareil.
#
#   outils/installer.sh            # iPhone, iPad, Apple TV et Mac
#   outils/installer.sh --iphone   # iPhone seulement
#   outils/installer.sh --ipad     # iPad seulement
#   outils/installer.sh --mac      # Mac seulement
#   outils/installer.sh --tv       # Apple TV seulement
#
# Un iPhone ou un iPad doit être jumelé avec ce Mac, sous iOS ou iPadOS 26, et avoir le mode développeur activé
# (Réglages › Confidentialité et sécurité › Mode développeur).
# L'Apple TV doit être jumelée (xcrun devicectl manage pair, la TV sur Réglages › Télécommandes et appareils ›
# App Remote et appareils) et réveillée ; son profil se crée avec le compte Apple connecté dans Xcode › Settings › Accounts.
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
tv=true
case "${1:-}" in
  --iphone) mac=false; ipad=false; tv=false ;;
  --ipad) mac=false; iphone=false; tv=false ;;
  --mac) iphone=false; ipad=false; tv=false ;;
  --tv) iphone=false; ipad=false; mac=false ;;
  "") ;;
  *) echo "Option inconnue : $1 (--iphone, --ipad, --mac ou --tv)"; exit 2 ;;
esac

echecs=false
mkdir -p "$racine/.build"
"$racine/outils/generer-projet.sh" > /dev/null

schema=Seance
# L'heure de chaque compilation va dans l'Info.plist (SeanceCompileeLe) : c'est l'heure d'installation que montrent
# À propos et Versions (8.2.1).
xcode() {
  local destination=$1 nom=$2; shift 2
  if ! xcodebuild -project "$projet" -scheme $schema -configuration Release -destination "$destination" \
      -derivedDataPath "$derives" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      SEANCE_COMPILEE_LE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$@" > "$journal" 2>&1; then
    grep -E 'error:' "$journal" | sort -u | head -20
    # Un appareil verrouillé ou endormi n'est pas une erreur de compilation : on le dit, et on passe aux autres.
    if grep -q -i -E "needs to be unlocked|Timed out waiting for all destinations" "$journal"; then
      echo "${nom#l\'} : appareil verrouillé ou injoignable — déverrouille-le, puis relance pour lui seul."
    else
      echo "La compilation pour $nom a échoué. Journal complet : $journal"
    fi
    return 1
  fi
}

# Compile, puis vérifie la signature du produit. Une compilation incrémentale réécrit parfois les métadonnées
# App Intents du widget après sa signature (« a sealed resource is missing or invalid ») : tout est alors recompilé.
compiler() {
  local destination=$1 nom=$2 app=$3
  echo "Compilation pour $nom…"
  xcode "$destination" "$nom" build || return 1
  if ! codesign --verify --deep --strict "$app" 2> /dev/null; then
    echo "Signature incohérente après une compilation incrémentale : recompilation complète pour $nom…"
    xcode "$destination" "$nom" clean build || return 1
    codesign --verify --deep --strict "$app"
  fi
}

version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1"
}

# Les appareils physiques branchés et jumelés : « identifiant<TAB>modèle », l'identifiant précédant « (UDID) ».
appareils() {
  # « connected » quand un tunnel est déjà ouvert ; l'espace écarte « unavailable ».
  # Une Apple TV jumelée figure dans la même liste : ce n'est ni un iPhone ni un iPad (voir appareils_tv).
  xcrun devicectl list devices 2>/dev/null | awk '/physical/ && / (available|connected)/ && !/AppleTV/ {
    for (i = 1; i < NF; i++) if ($(i+1) == "(UDID)") { id = $i }
    modele = ($0 ~ /iPad/) ? "iPad" : "iPhone"
    print id "\t" modele
  }'
}

# Les Apple TV jumelées et joignables : leur identifiant.
appareils_tv() {
  # « physical » : les simulateurs d'Apple TV portent le même modèle (AppleTV14,1) et figurent dans la même liste.
  xcrun devicectl list devices 2>/dev/null | awk '/AppleTV/ && /physical/ && / (available|connected)/ {
    for (i = 1; i < NF; i++) if ($(i+1) == "(UDID)") print $i
  }'
}

installer_sur_tv() {
  local udid=$1
  local app="$derives/Build/Products/Release-appletvos/SeanceTV.app"
  schema=SeanceTV
  compiler "platform=tvOS,id=$udid" "l'Apple TV" "$app" || { schema=Seance; return 1; }
  schema=Seance
  if ! xcrun devicectl device install app --device "$udid" "$app" > "$journal.installation" 2>&1; then
    grep -i -E "error|asleep|developer mode|minimum|version" "$journal.installation" | head -5
    echo "Apple TV : l'installation a échoué. Vérifie qu'elle est réveillée et sur le même réseau que ce Mac."
    return 1
  fi
  echo "Apple TV : Séance $(version "$app/Info.plist") installée."
}

installer_sur() {
  local udid=$1 nom=$2
  local app="$derives/Build/Products/Release-iphoneos/Seance.app"
  # Compiler pour cet appareil l'inscrit au profil d'installation du compte gratuit.
  compiler "id=$udid" "$nom" "$app" || return 1
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
    installer_sur "$udid" "$nom" || echecs=true
  done < <(appareils)
  if ! $trouve; then
    echo "Aucun iPhone ni iPad disponible : branche-le, déverrouille-le, active son mode développeur, puis relance."
    $mac || exit 1
  fi
fi

if $tv; then
  trouvee=false
  while read -r udid; do
    [[ -z $udid ]] && continue
    trouvee=true
    installer_sur_tv "$udid" || echecs=true
  done < <(appareils_tv)
  # Sans option, une TV éteinte ou absente n'empêche pas d'installer le reste.
  if ! $trouvee; then
    echo "Apple TV : aucune n'est joignable (éteinte, en veille prolongée ou pas jumelée)."
    $mac || $iphone || $ipad || exit 1
  fi
fi

if $mac; then
  app="$derives/Build/Products/Release-maccatalyst/Seance.app"
  compiler "platform=macOS,variant=Mac Catalyst" "le Mac" "$app" || exit 1
  ouverte=false
  # L'app du Mac seulement : une copie qui tourne dans un simulateur porte le même nom de processus.
  # Par motif : le « é » du chemin n'est pas encodé de la même façon dans la ligne de commande du processus.
  surLeMac() { pgrep -f "^/Applications/[^/]*\.app/Contents/MacOS/Seance" > /dev/null; }
  if surLeMac; then
    ouverte=true
    # Une feuille ouverte (filtres, bande-annonce) fait refuser la fermeture : rien n'est remplacé dans ce cas.
    osascript -e 'quit app id "ch.patrick.seance"' > /dev/null 2>&1 || true
    for _ in {1..20}; do surLeMac || break; sleep 0.5; done
    if surLeMac; then
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

if $echecs; then
  echo "Au moins un appareil n'a pas pu être mis à jour (voir plus haut)."
  exit 1
fi

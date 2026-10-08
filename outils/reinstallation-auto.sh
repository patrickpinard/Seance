#!/bin/zsh
# Réinstallation automatique (8.12) : lancé une fois par jour par le Mac mini (outils/programmer-reinstallation.sh),
# il réinstalle Séance sur chaque type d'appareil dont la dernière installation réussie date de plus de 4 jours — avant
# les 7 jours au bout desquels l'app gratuite cesse de s'ouvrir. Un appareil endormi ou verrouillé sera repris le
# lendemain : à 4 jours, il reste trois essais avant l'expiration.
#
# Par prudence, rien n'est installé si le projet n'est pas sur `main`, ou s'il a des modifications pas encore
# enregistrées : on n'envoie jamais un travail en cours sur les appareils de la famille. Ni pendant une autre
# compilation (une session de travail, ou le passage précédent qui n'est pas fini).
#
#   outils/reinstallation-auto.sh            # un passage, comme le fait le Mac mini
#   outils/reinstallation-auto.sh --forcer   # tout réinstaller tout de suite, quel que soit l'âge des installations
set -uo pipefail
racine=${0:A:h:h}
etat="$HOME/Library/Application Support/Seance"
memoire="$etat/reinstallations.tsv"
journal="$HOME/Library/Logs/Seance-reinstallation.log"
verrou="$etat/reinstallation.verrou"
age_max=$((4 * 86400))
forcer=false
[[ ${1:-} == --forcer ]] && forcer=true

mkdir -p "$etat" "${journal:h}"
touch "$memoire"
noter() { print -r -- "$(date '+%Y-%m-%d %H:%M') $*" >> "$journal"; }
prevenir() { osascript -e "display notification \"$1\" with title \"Séance\" subtitle \"Réinstallation automatique\"" > /dev/null 2>&1 || true; }

# Un seul passage à la fois.
if ! mkdir "$verrou" 2> /dev/null; then
  # Un verrou de plus de 3 heures est celui d'un passage interrompu.
  if [[ -n $(find "$verrou" -maxdepth 0 -mmin +180 2> /dev/null) ]]; then rmdir "$verrou" 2> /dev/null; mkdir "$verrou" || exit 0; else exit 0; fi
fi
trap 'rmdir "$verrou" 2> /dev/null' EXIT

cd "$racine" || exit 1
branche=$(git rev-parse --abbrev-ref HEAD 2> /dev/null)
if [[ $branche != main ]]; then noter "Passage sauté : le projet est sur la branche « $branche », pas sur main."; exit 0; fi
if [[ -n $(git status --porcelain 2> /dev/null) ]]; then noter "Passage sauté : des modifications ne sont pas enregistrées."; exit 0; fi
if pgrep -x xcodebuild > /dev/null; then noter "Passage sauté : une autre compilation est en cours."; exit 0; fi

# Une fois par jour au plus, même lancé à la main sans --forcer.
aujourdhui=$(date +%Y-%m-%d)
if ! $forcer && [[ $(cat "$etat/dernier-passage" 2> /dev/null) == $aujourdhui ]]; then exit 0; fi
print -r -- $aujourdhui > "$etat/dernier-passage"

maintenant=$(date +%s)
derniere() { awk -F'\t' -v c="$1" '$1 == c { print $2 }' "$memoire" | tail -1; }
retenir() {
  awk -F'\t' -v c="$1" '$1 != c' "$memoire" > "$memoire.tmp"
  print -r -- "$1	$maintenant" >> "$memoire.tmp"
  mv "$memoire.tmp" "$memoire"
}

reussies=()
# Les échecs qui méritent une alerte (8.12) : le compte ou la signature d'Xcode, une compilation cassée, ou un appareil
# qui n'a plus été réinstallé depuis 6 jours (il expire le lendemain). Un appareil simplement endormi ou verrouillé ne
# prévient pas : il sera repris le lendemain.
compte_xcode=false
alertes=()
for cible in tv iphone ipad mac; do
  avant=$(derniere $cible)
  if ! $forcer && [[ -n $avant ]] && (( maintenant - avant < age_max )); then continue; fi
  sortie=$("$racine/outils/installer.sh" --$cible 2>&1)
  if print -r -- "$sortie" | grep -q "installée"; then
    retenir $cible
    reussies+=$cible
    noter "$cible : $(print -r -- "$sortie" | grep "installée" | tr '\n' ' ')"
  else
    noter "$cible : pas encore — $(print -r -- "$sortie" | tail -1)"
    if print -r -- "$sortie" | grep -q -E "No Accounts|Signing certificate is invalid|No profiles for|doesn't include the currently selected device"; then
      compte_xcode=true
    elif print -r -- "$sortie" | grep -q "La compilation pour .* a échoué"; then
      alertes+="la compilation pour $cible a échoué"
    elif [[ -n $avant ]] && (( maintenant - avant > 6 * 86400 )); then
      alertes+="$cible n'a plus été réinstallé depuis 6 jours (expire bientôt)"
    fi
  fi
done

if $compte_xcode; then
  prevenir "Échec : Xcode a perdu ton compte Apple ou son certificat. Reconnecte-le dans Xcode › Réglages › Comptes."
  noter "ALERTE : compte ou certificat d'Xcode à reconnecter."
fi
if (( ${#alertes} > 0 )); then
  prevenir "Échec : ${(j:, :)alertes}. Détails : ~/Library/Logs/Seance-reinstallation.log"
  noter "ALERTE : ${(j:, :)alertes}"
fi

if (( ${#reussies} > 0 )); then
  prevenir "Séance réinstallée : ${(j:, :)reussies}. Valable 7 jours de plus."
fi

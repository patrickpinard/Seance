#!/bin/zsh
# Réinstallation automatique (8.11) : lancé toutes les deux heures par le Mac mini (outils/programmer-reinstallation.sh),
# il réinstalle Séance sur chaque type d'appareil dont la dernière installation réussie date de plus de 4 jours — avant
# les 7 jours au bout desquels l'app gratuite cesse de s'ouvrir. Un appareil endormi ou verrouillé sera repris au passage
# suivant.
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

maintenant=$(date +%s)
derniere() { awk -F'\t' -v c="$1" '$1 == c { print $2 }' "$memoire" | tail -1; }
retenir() {
  awk -F'\t' -v c="$1" '$1 != c' "$memoire" > "$memoire.tmp"
  print -r -- "$1	$maintenant" >> "$memoire.tmp"
  mv "$memoire.tmp" "$memoire"
}

reussies=()
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
  fi
done

if (( ${#reussies} > 0 )); then
  prevenir "Séance réinstallée : ${(j:, :)reussies}. Valable 7 jours de plus."
fi

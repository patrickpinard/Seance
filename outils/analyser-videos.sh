#!/bin/zsh
# Dresse l'inventaire des vidéos personnelles du NAS : pour chaque fichier, son codec vidéo, son codec audio, sa
# définition, sa durée — et si l'iPhone sait la lire telle quelle. Ne modifie rien.
#
#   outils/analyser-videos.sh /Volumes/Videos            # tout le partage
#   outils/analyser-videos.sh /Volumes/Videos 2013       # un dossier
#
# Le partage doit être monté (Finder › Aller › Se connecter au serveur, smb://192.168.1.220/Videos).
# Résultat : un tableau à l'écran et un fichier .build/videos-nas.tsv, lu par outils/convertir-videos.sh.
set -uo pipefail
racine=${0:A:h:h}
depart=${1:-/Volumes/Videos}
[[ -d $depart ]] || { echo "Partage introuvable : $depart — monte-le d'abord dans le Finder."; exit 1 }
sortie="$racine/.build/videos-nas.tsv"
mkdir -p "$racine/.build"

# Ce qu'AVFoundation lit sur l'iPhone : le conteneur ET le codec doivent tous deux convenir.
conteneursLus=(mp4 m4v mov qt)
codecsVideoLus=(h264 hevc)
codecsAudioLus=(aac mp3 alac pcm_s16le pcm_s24le)

contient() { local aiguille=$1; shift; for element in "$@"; do [[ $element == "$aiguille" ]] && return 0; done; return 1 }

printf 'fichier\tconteneur\tvideo\taudio\tdefinition\tsecondes\toctets\tverdict\n' > "$sortie"
total=0; lus=0; aConvertir=0
print -P "%B%F{cyan}Fichier                                             Vidéo      Audio      Définition   Verdict%f%b"

find "$depart" -type f \( -iname "*.avi" -o -iname "*.wmv" -o -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.mp4" \
  -o -iname "*.m4v" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.3gp" -o -iname "*.flv" \) 2>/dev/null | sort | while read -r fichier; do
  nom=${fichier#$depart/}
  conteneur=${fichier:e:l}
  donnees=$(ffprobe -v quiet -print_format default=noprint_wrappers=1 -show_entries \
    "stream=codec_type,codec_name,width,height:format=duration,size" "$fichier" 2>/dev/null)
  [[ -n $donnees ]] || { printf '%s\t%s\t?\t?\t?\t0\t0\tillisible\n' "$nom" "$conteneur" >> "$sortie"; continue }

  video=$(print -r -- "$donnees" | awk -F= '/^codec_name=/ {noms[++n]=$2} /^codec_type=video/ {v=n} END {print noms[v]}')
  audio=$(print -r -- "$donnees" | awk -F= '/^codec_name=/ {noms[++n]=$2} /^codec_type=audio/ {a=n} END {print noms[a]}')
  largeur=$(print -r -- "$donnees" | awk -F= '/^width=/ {print $2; exit}')
  hauteur=$(print -r -- "$donnees" | awk -F= '/^height=/ {print $2; exit}')
  duree=$(print -r -- "$donnees" | awk -F= '/^duration=/ {printf "%.0f", $2; exit}')
  taille=$(print -r -- "$donnees" | awk -F= '/^size=/ {print $2; exit}')

  # Quatre verdicts : « lit » (rien à faire), « remuxer » (bons codecs, mauvais conteneur), « son » (l'image
  # convient, seul le son est à refaire — on la recopie telle quelle) et « convertir » (tout est à reprendre).
  if contient "$video" $codecsVideoLus; then
    if contient "$audio" $codecsAudioLus; then
      if contient "$conteneur" $conteneursLus; then verdict=lit; else verdict=remuxer; fi
    else
      verdict=son
    fi
  else
    verdict=convertir
  fi
  [[ $verdict == lit ]] && ((lus++)) || ((aConvertir++))
  ((total++))

  printf '%s\t%s\t%s\t%s\t%sx%s\t%s\t%s\t%s\n' "$nom" "$conteneur" "${video:-aucun}" "${audio:-aucun}" \
    "${largeur:-?}" "${hauteur:-?}" "${duree:-0}" "${taille:-0}" "$verdict" >> "$sortie"
  couleur=green; [[ $verdict == convertir ]] && couleur=yellow
  [[ $verdict == remuxer || $verdict == son ]] && couleur=blue
  printf "%-50.50s %-10.10s %-10.10s %-12.12s " "$nom" "${video:-aucun}" "${audio:-aucun}" "${largeur:-?}x${hauteur:-?}"
  print -P "%F{$couleur}$verdict%f"
done

print ""
print -P "%BRésultat%b : $(wc -l < "$sortie" | tr -d ' ') lignes dans .build/videos-nas.tsv"
awk -F'\t' 'NR>1 {compte[$8]++; octets[$8]+=$7} END {for (v in compte) printf "  %-10s %3d fichiers  %6.1f Go\n", v, compte[v], octets[v]/1073741824}' "$sortie" | sort

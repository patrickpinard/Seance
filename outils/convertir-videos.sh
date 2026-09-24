#!/bin/zsh
# Convertit les vidéos du NAS que l'iPhone ne sait pas lire — AVI DivX, WMV, MOV de caméscope — en MP4 H.264,
# lisible par Séance, l'Apple TV, la Photothèque, tout. Lit l'inventaire de outils/analyser-videos.sh.
#
#   outils/analyser-videos.sh /Volumes/Videos     # d'abord : que faut-il convertir ?
#   outils/convertir-videos.sh --essai            # convertit UN fichier, pour juger le résultat
#   outils/convertir-videos.sh                    # convertit tout ce qui doit l'être
#   outils/convertir-videos.sh --remplacer        # … et range l'original dans « Originaux » à côté
#
# Ce que fait la conversion, et ce qu'elle ne fait pas :
#   · « remuxer » : les flux sont recopiés tels quels dans un MP4 — aucune perte, quelques secondes par fichier.
#   · « son » : l'image est déjà en H.264 ou HEVC, seul le son ne convient pas (du PCM, par exemple). L'image est
#     recopiée sans y toucher — aucune perte — et seul le son est refait en AAC.
#   · « convertir » : l'image est réencodée en H.264 (le codec d'origine, DivX ou MJPEG, n'existe pas sur iPhone).
#     Réglage : libx264 en CRF 18, « preset slow ». Mesuré sur un échantillon, il rend SSIM 0,999 — l'œil ne voit
#     aucune différence — et des fichiers plus petits que l'encodeur matériel du Mac, qui plafonne à 0,998.
#     Ce n'est pas du « sans perte » au sens strict : c'est impossible en gardant un fichier lisible partout.
#     RAPIDE=1 bascule sur l'encodeur matériel (VideoToolbox) : trois fois plus vite, un cheveu moins bon.
#   · L'original n'est JAMAIS effacé : sans --remplacer, le MP4 se pose à côté ; avec, l'original part dans
#     « Originaux/ » au même endroit. À toi d'effacer, quand tu auras vérifié.
#   · La date du fichier d'origine est recopiée sur le nouveau : Séance range les souvenirs par date.
set -uo pipefail
racine=${0:A:h:h}
inventaire="$racine/.build/videos-nas.tsv"
[[ -f $inventaire ]] || { echo "Lance d'abord outils/analyser-videos.sh"; exit 1 }
depart=${DEPART:-/Volumes/Videos}
[[ -d $depart ]] || { echo "Partage introuvable : $depart — monte-le dans le Finder."; exit 1 }

essai=false; remplacer=false
for argument in "$@"; do
  case $argument in
    --essai) essai=true ;;
    --remplacer) remplacer=true ;;
    *) echo "Argument inconnu : $argument"; exit 2 ;;
  esac
done

journal="$racine/.build/conversion.log"
: > "$journal"
faits=0; echecs=0; gagnes=0

# Les fichiers à traiter, tirés de l'inventaire : ceux qui ne se lisent pas tels quels.
lignes=$(awk -F'\t' 'NR>1 && ($8=="convertir" || $8=="remuxer" || $8=="son") {print}' "$inventaire")
[[ -n $lignes ]] || { echo "Rien à convertir : tout se lit déjà."; exit 0 }
$essai && lignes=$(print -r -- "$lignes" | head -1)

nombre=$(print -r -- "$lignes" | wc -l | tr -d ' ')
print -P "%B$nombre fichier(s) à traiter%b — journal : .build/conversion.log"

print -r -- "$lignes" | while IFS=$'\t' read -r nom conteneur video audio definition secondes octets verdict; do
  source="$depart/$nom"
  [[ -f $source ]] || { echo "Absent : $nom" | tee -a "$journal"; ((echecs++)); continue }
  cible="${source:r}.mp4"
  [[ $source == $cible ]] && cible="${source:r}-iphone.mp4"
  if [[ -f $cible ]]; then echo "Déjà converti : ${cible:t}" | tee -a "$journal"; continue; fi

  printf "%-52.52s %s… " "${nom:t}" "$verdict"
  debut=$SECONDS
  if [[ $verdict == remuxer ]]; then
    # Les codecs conviennent : on change seulement de boîte. Rien n'est réencodé, rien n'est perdu.
    ffmpeg -nostdin -v error -i "$source" -c copy -movflags +faststart "$cible" -y >> "$journal" 2>&1
  elif [[ $verdict == son ]]; then
    # L'image convient déjà : elle est recopiée telle quelle, sans y toucher. Seul le son est refait en AAC.
    ffmpeg -nostdin -v error -i "$source" -c:v copy -c:a aac -b:a 192k -ac 2 \
      -movflags +faststart -map_metadata 0 "$cible" -y >> "$journal" 2>&1
  else
    # Réencodage. -movflags +faststart met l'index en tête : la lecture démarre sans lire tout le fichier.
    #
    # Le réglage dépend de la source. Un DV, un MJPEG ou un AIC de caméscope compresse chaque image séparément :
    # son débit est énorme et CRF 18 divise la taille par vingt sans rien perdre à l'œil. Un WMV ou un MPEG-4,
    # lui, est déjà compressé serré : à CRF 18, H.264 s'applique à garder jusqu'au bruit de compression et le
    # fichier grossit (mesuré : 344 Mo devenus 445). Pour ceux-là, un CRF un peu plus souple et un plafond de
    # débit calé sur la source — on ne grossit jamais.
    debitSource=0
    [[ ${secondes:-0} -gt 0 ]] && debitSource=$(( octets * 8 / secondes / 1000 ))
    if [[ $video == (dvvideo|mjpeg|aic|rawvideo|prores) ]]; then
      qualite=18; plafond=()
    else
      qualite=20
      [[ $debitSource -gt 0 ]] && plafond=(-maxrate "${debitSource}k" -bufsize "$(( debitSource * 2 ))k") || plafond=()
    fi
    if [[ ${RAPIDE:-0} == 1 ]]; then
      encodeur=(-c:v h264_videotoolbox -q:v 65 -profile:v high)
    else
      encodeur=(-c:v libx264 -crf $qualite -preset slow -profile:v high $plafond)
    fi
    ffmpeg -nostdin -v error -i "$source" \
      $encodeur -pix_fmt yuv420p \
      -c:a aac -b:a 192k -ac 2 \
      -movflags +faststart -map_metadata 0 "$cible" -y >> "$journal" 2>&1
  fi
  etat=$?
  duree=$((SECONDS - debut))

  if [[ $etat -ne 0 || ! -s $cible ]]; then
    print -P "%F{red}échec%f (voir le journal)"
    rm -f "$cible"; ((echecs++)); continue
  fi
  # La date d'origine : Séance range les souvenirs par date, elle ne doit pas devenir celle de la conversion.
  touch -r "$source" "$cible"
  avant=$(stat -f %z "$source"); apres=$(stat -f %z "$cible")
  print -P "%F{green}fait%f  ${duree}s  $((avant / 1048576)) → $((apres / 1048576)) Mo"
  ((faits++)); gagnes=$((gagnes + avant - apres))

  if $remplacer; then
    dossierOriginaux="${source:h}/Originaux"
    mkdir -p "$dossierOriginaux"
    mv "$source" "$dossierOriginaux/"
  fi
done

print ""
print -P "%B$faits converti(s), $echecs échec(s)%b"
$remplacer && print "Les originaux sont dans les dossiers « Originaux » — à effacer quand tu auras vérifié."
$essai && print -P "%F{cyan}C'était un essai sur un seul fichier : regarde-le, puis relance sans --essai.%f"

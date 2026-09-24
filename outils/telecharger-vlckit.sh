#!/bin/zsh
# Télécharge VLCKit — le moteur de VLC — dans .build/vlckit, d'où project.yml le prend. Il pèse 821 Mo compressé,
# 2,7 Go une fois ouvert : il reste hors du dépôt, comme XcodeGen. À relancer après un .build effacé.
#
#   outils/telecharger-vlckit.sh
#
# Le binaire officiel n'a pas de tranche Mac Catalyst. Séance n'appelle VLCKit que sur l'iPhone, l'iPad et
# l'Apple TV (son code est sous `#if !targetEnvironment(macCatalyst)`), mais l'éditeur de liens du Mac réclame
# quand même une bibliothèque à ce nom : ce script lui en fabrique une, vide, ce qui suffit puisqu'aucun symbole
# n'est référencé de ce côté.
set -uo pipefail
racine=${0:A:h:h}
version=4.0.0-alpha.21
adresse="https://github.com/virtualox/vlckit-spm/releases/download/$version/VLCKit.xcframework.zip"
dossier="$racine/.build/vlckit"
cadre="$dossier/VLCKit.xcframework"

if [[ -d "$cadre/ios-arm64_x86_64-maccatalyst" ]]; then
  echo "VLCKit est déjà là : $cadre"
  exit 0
fi

mkdir -p "$dossier"
archive="$dossier/VLCKit.zip"
if [[ ! -s $archive ]]; then
  echo "Téléchargement de VLCKit $version (821 Mo)…"
  curl -L --progress-bar -o "$archive" "$adresse" || { echo "Le téléchargement a échoué."; exit 1 }
fi

echo "Ouverture de l'archive…"
(cd "$dossier" && unzip -q -o VLCKit.zip) || { echo "L'archive est illisible."; exit 1 }
[[ -d $cadre ]] || { echo "VLCKit.xcframework est introuvable dans l'archive."; exit 1 }

# La tranche Mac Catalyst, vide : elle n'existe que pour l'éditeur de liens.
echo "Ajout de la tranche Mac Catalyst (vide)…"
travail=$(mktemp -d)
cat > "$travail/vide.c" <<'FIN'
// Tranche Mac Catalyst de VLCKit : vide, et c'est voulu. Séance n'appelle VLCKit que sur l'iPhone, l'iPad et
// l'Apple TV ; le Mac n'a donc aucun symbole à résoudre.
FIN
for arche in arm64 x86_64; do
  xcrun clang -target "$arche-apple-ios17.0-macabi" -c "$travail/vide.c" -o "$travail/vide-$arche.o" || exit 1
  xcrun libtool -static -o "$travail/lib-$arche.a" "$travail/vide-$arche.o" 2>/dev/null
done
xcrun lipo -create "$travail/lib-arm64.a" "$travail/lib-x86_64.a" -output "$travail/VLCKit" || exit 1

tranche="$cadre/ios-arm64_x86_64-maccatalyst/VLCKit.framework"
mkdir -p "$tranche/Versions/A/Resources"
cp "$travail/VLCKit" "$tranche/Versions/A/VLCKit"
cat > "$tranche/Versions/A/Resources/Info.plist" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>VLCKit</string>
  <key>CFBundleIdentifier</key><string>org.videolan.vlckit</string>
  <key>CFBundleName</key><string>VLCKit</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>4.0.0</string>
  <key>CFBundleVersion</key><string>4.0.0</string>
  <key>MinimumOSVersion</key><string>17.0</string>
</dict>
</plist>
FIN
(cd "$tranche" && ln -sf A Versions/Current && ln -sf Versions/Current/VLCKit VLCKit && ln -sf Versions/Current/Resources Resources)
rm -rf "$travail"

python3 - "$cadre/Info.plist" <<'FIN'
import plistlib, sys
chemin = sys.argv[1]
d = plistlib.load(open(chemin, "rb"))
if not any(l["LibraryIdentifier"] == "ios-arm64_x86_64-maccatalyst" for l in d["AvailableLibraries"]):
    d["AvailableLibraries"].append({
        "BinaryPath": "VLCKit.framework/VLCKit",
        "LibraryIdentifier": "ios-arm64_x86_64-maccatalyst",
        "LibraryPath": "VLCKit.framework",
        "SupportedArchitectures": ["arm64", "x86_64"],
        "SupportedPlatform": "ios",
        "SupportedPlatformVariant": "maccatalyst",
    })
    plistlib.dump(d, open(chemin, "wb"))
print("tranches :", ", ".join(sorted(l["LibraryIdentifier"] for l in d["AvailableLibraries"])))
FIN

rm -f "$archive"
echo "VLCKit est prêt : $cadre"

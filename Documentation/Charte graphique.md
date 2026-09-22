# Séance — charte graphique

L'identité visuelle et les règles d'interface de Séance, sur l'iPhone, l'iPad, le Mac et l'Apple TV.
Ce document dit **quoi utiliser et où le trouver dans le code**. Toute nouvelle page s'y conforme ; s'il faut s'en
écarter, on change d'abord la charte, puis toutes les pages.

Source de vérité du code : `Seance/Design/` (iPhone, iPad, Mac) et `SeanceTV/Design/` (Apple TV).
`Theme.swift` est partagé par les deux.

## 1. L'esprit

Une salle obscure, et la lumière du projecteur. Le fond est presque noir, les images des films font la couleur, et
**un seul accent, l'orange braise**, désigne ce qui se touche et ce qui compte. Pas d'arc-en-ciel d'icônes, pas de gris
d'administration : chaque écran doit pouvoir passer pour une page du même livre.

Le ton des textes est direct et tutoie : « Ta soirée », « Tes goûts », « Rien de prévu ce soir ».

## 2. Couleurs

| Rôle | Nom dans le code | Sombre | Clair |
|---|---|---|---|
| Accent (boutons, sélection) | `Theme.accent` | `#FF6A3D` | `#FF6A3D` |
| Accent des textes et icônes | `Theme.accentClair` | `#FFA24A` | `#AD4505` (contraste 5,3:1) |
| Dégradé des boutons principaux | `Theme.degradeAccent` | `#FF6A3D` → `#FFA24A`, en diagonale | identique |
| Fond de page | `Theme.fond` | `#0A0A0E` | `#F6F5F4` |
| Cartes, tuiles, puces | `Theme.surface` | blanc à 8 % | noir à 6 % |
| Filets et contours | `Theme.trait` | blanc à 12 % | noir à 12 % |

- **Sur le dégradé orange, le texte est noir**, jamais blanc.
- **Vert et orange d'état** : `Color.green` = en ordre, `Color.orange` = à régler. Réservés à l'état (Réglages, étapes),
  jamais décoratifs.
- **Note TMDB** : vert dès 70 %, jaune de 40 à 69 %, rouge en dessous (`Theme.couleurNote`).
- **Interdit** : les icônes sur pastilles de couleurs variées (rose, violet, bleu…), façon Réglages d'iOS. Un symbole
  est orange (`accentClair`) ou de la couleur du texte.
- Les grandes cartes-images restent sombres quelle que soit l'apparence (`.surImage()`), pour que leur texte blanc se
  lise sur la photo.

## 3. Typographie

Police du système, en styles dynamiques (`.headline`, `.subheadline`, `.caption`…) : le texte suit la taille choisie
dans iOS, jusqu'aux tailles d'accessibilité. Pas de taille fixe sur l'iPhone, sauf pour un chiffre-vedette (l'heure
d'un passage télé, un code).

- Titres de page et de section : gras à très gras (`.bold`, `.heavy`).
- Un titre sous une affiche : deux lignes, place réservée (`lineLimit(2, reservesSpace: true)`), pour que les
  sous-titres restent alignés.
- Apple TV : tailles fixes, lisibles à trois mètres — 58 à 76 pt pour un titre de page, 38 pt pour une étagère,
  26 à 30 pt pour le texte courant, jamais moins de 22 pt.

## 4. Formes

- Coins arrondis continus partout (`style: .continuous`) : 13 pt pour une case de sélecteur, 16 à 18 pt pour une
  carte ou une tuile, 20 à 30 pt sur l'Apple TV.
- Marges de page : 20 pt sur l'iPhone ; 80 pt sur l'Apple TV (`MargesTV.bord`), la zone que certains téléviseurs rognent.
- Affiches au format 2:3, grandes cartes au format 16:9.

## 5. Composants — lequel pour quoi

| Besoin | Composant | Fichier |
|---|---|---|
| Choisir **ce que la page montre** (onglets de Mes listes, source d'Explorer, Films / Séries, rayons du NAS) | `SelecteurCases` | `Seance/Design/SelecteurCases.swift` |
| Grille ou liste | `BasculeGrilleListe` | `Seance/Design/BasculeGrilleListe.swift` |
| Un réglage, un dossier, une entrée de menu | `TuileReglage` (symbole orange, titre, état) | `Seance/Ecrans/Reglages/ReglagesView.swift` |
| **Un titre, partout** (accueil, Ce soir, Mes listes, Explorer, NAS, Documentaires, Favoris, filmographie) | `CarteLargeTitre` : **le format unique**, 16/9, celui de « Ce soir à la TV » — image en plein cadre, où regarder en haut à gauche, ligne orange (source, chaîne et heure), titre, puis type, année, durée, note. Initialiseurs pour `TitreResume`, `Suivi`, `FichierNAS`, `ApercuTitre`, `Favori`, `Echeance` | `Seance/Design/CarteLargeTitre.swift` |
| **Un souvenir** (vidéos personnelles, 6.2) | `CarteLargeTitre` en mode icône (`icone`, `etiquette` ALBUM ou VIDÉO, `lectureEnCoin`) : pas d'image, `FondSouvenir` — un halo orange sur le noir et la grande icône choisie, un SF Symbol de `IconesSouvenirs` (vingt-quatre, en orange). Feuille « Couverture » pour la choisir. Sur la TV : `CarteLargeTV(icone:)` | `Seance/Design/CarteLargeTitre.swift`, `Seance/Ecrans/NAS/VideosPerso.swift` |
| Un titre du NAS | `CarteLargeNAS` (même carte, avec « NEW » et la qualité) | `Seance/Ecrans/NAS/NASView.swift` |
| Un passage à la TV | `CarteDiffusion` (même carte, avec l'heure, la durée, la chaîne et la cloche) | `Seance/Ecrans/Accueil/ProgrammeTele.swift` |
| Un réglage surveillé (en ordre / à régler), en grande carte | `CarteReglage` (affiche floutée en fond, symbole orange, pastille d'état) ; `CarteReglageTV` sur l'Apple TV | idem ; `SeanceTV/Design/CarteReglageTV.swift` |
| Une ligne d'état (en ordre / à régler) | `LigneEtat` | idem |
| Une page sans contenu | `EtatVide` : symbole, titre, phrase, action | `Seance/Design/EtatVide.swift` |
| Un titre de section | `TitreSection` | `Seance/Design/Composants.swift` |
| Une image distante | `ImageDistante` | idem |
| Un filtre qu'on allume | `PuceFiltre` | idem |
| **Où regarder** un titre, tout de suite (soirée, idées, recherche, propositions) | `ActionsOuRegarder` : pastilles qui agissent — « Lire sur le NAS », la plateforme (ouvre sa recherche sur le titre), la chaîne avec le jour et l'heure ; `PastilleOuRegarder` pour le dessin | `Seance/Design/OuRegarder.swift` |
| **Lancer** ce qui est prévu, d'un seul geste (carte de soirée) | `ActionsOuRegarder(presentation: .boutonUnique)` : un grand bouton qui choisit la source — NAS, puis plateforme, puis chaîne — et dit les autres dessous ; `EtiquetteGrandBouton` pour le dessin | idem |
| Lire une vidéo personnelle sans quitter l'app | `LecteurIntegre` (AVPlayer sur le relais local `RelaisVideo`) | `Seance/Ecrans/NAS/LecteurIntegre.swift` |
| ★ Les favoris, en grille avec le partage | `SectionFavoris` (onglet Favoris de Mes listes) | `Seance/Ecrans/MesListes/SectionFavoris.swift` |
| Les documentaires et leurs thèmes | `DocumentairesView`, thèmes en `PuceFiltre` | `Seance/Ecrans/Documentaires/DocumentairesView.swift` |
| Où regarder, en coin d'affiche et en tête de fiche | `BadgeOu`, `RangeeOu` | `Seance/Etat/EtatOu.swift` |
| Apple TV : bouton d'action | `BoutonTV` (orange = action principale ; blanc à texte noir quand il a le focus) | `SeanceTV/Design/ComposantsTV.swift` |
| Apple TV : un titre | `CarteLargeTV` — la même carte 16/9 que sur l'iPhone, en 520 points dans les grilles et 620 sur l'accueil. `AfficheTV` (2:3) ne sert plus qu'aux **portraits d'acteurs**. Étagère et page vide : `EtagereTV`, `VideTV` | idem |
| Apple TV : tuile et ligne qui se choisit | `TuileTV`, `LigneTV` | `SeanceTV/Ecrans/ReglagesTV.swift` |
| Apple TV : choisir ce que la page montre | `SelecteurTV` | `SeanceTV/Design/ComposantsTV.swift` |
| Apple TV : une tuile de jour | `TuileJourTV` | idem |
| Apple TV : une page de réglage | `PageTV`, `SectionTV`, `LigneTVReglage`, `BoutTV`, `ChampTV`, `BasculeTV` | `SeanceTV/Design/ReglagesComposantsTV.swift` |

Règles :

- **Le sélecteur de Séance, c'est `SelecteurCases`** : des cases de même largeur, l'active en dégradé orange à texte
  noir, les autres sur `Theme.surface`. Avec symbole (50 pt de haut) pour des sections de nature différente, sans
  symbole (40 pt) pour Films / Séries. Le contrôle segmenté gris d'iOS ne sert **que dans les formulaires de réglage**.
- **Un seul format pour un film ou une série** : la grande carte 16/9 (`CarteLargeTitre`), partout et sur tous les
  appareils — accueil, Ce soir, Mes listes, Explorer, programme TV, NAS, Documentaires, Favoris, filmographie, et
  l'Apple TV avec `CarteLargeTV`. On y voit d'un coup l'image, où regarder (source, chaîne, heure), le titre, la
  durée et la note. Les affiches 2:3 ne servent plus qu'aux **portraits d'acteurs**.
- **Un bouton principal par écran**, en dégradé orange ; les autres sont sur surface, ou en texte orange.
- **Toute zone qui se touche fait 44 pt au moins**, même dessinée plus petite (`.zoneDeToucher()`). Un test
  automatique le vérifie (`AccessibiliteTests`).
- **Une page vide explique** : ce qu'elle montrera, comment la remplir, et le bouton qui y mène. Jamais une ligne
  grise en haut d'une page noire.
- **Pas de réglage en double** : une seule entrée par réglage (dans les Réglages, l'état en tête est cette entrée).
- **Sur l'Apple TV, jamais de `Form` ni de `List` du système** : leur page est transparente (le texte de la page
  précédente se lit au travers) et leurs lignes passent au blanc sans changer la couleur d'un texte secondaire, qui
  devient blanc sur blanc. Une page se construit avec `PageTV` (fond opaque) et `SectionTV`, et **chaque état de
  couleur au focus est explicite** : texte noir, secondaire noir à 65 %.
- **« Où regarder » se montre avant tout le reste** : c'est la raison d'être de Séance. Partout où un titre est proposé
  pour être regardé, `ActionsOuRegarder` dit où — selon les seules plateformes cochées — et permet d'y aller d'un toucher.
- **Sur l'Apple TV, le menu est en haut, à l'horizontale, en noms seuls** (comme Netflix) : huit entrées au plus, sans icône.
- **Les listes de dates et les agendas mensuels sont proscrits** : un jour se choisit dans une rangée de tuiles.

## 6. Navigation

- Apple TV : la grande image d'accueil occupe toute la largeur, avec le titre et ses actions en bas à gauche, et les
  étagères dessous — comme les apps de télévision. La barre latérale repliée laisse une pastille en haut à gauche :
  les pages commencent dessous (`sousLaPastille()`), et chaque page poussée traite la touche Retour (`pageOuverte()`).
- iPhone : barre d'onglets en bas (Accueil, Ce soir, Mes listes, Profil) et la recherche. iPad et Mac : barre latérale.
- Une affiche ouvre sa fiche, partout. La navigation se fait **par valeur** (`NavigationLink(value:)`).
- Une action confirme en bas d'écran par un bandeau court (« ajouté à ta soirée »), qui propose d'annuler quand c'est
  possible.

## 7. Mouvement

Discret : `.snappy` pour un changement de sélection, 0,15 à 0,2 s pour un fondu ou un focus. Rien ne rebondit, rien
ne clignote. Sur l'Apple TV, l'élément qui a le focus grandit légèrement (2 à 8 %) et s'éclaire.

## 8. Logo et icône

Le billet de cinéma orange, incliné, marqué du triangle « lecture », sur fond de salle obscure réchauffée par le
faisceau du projecteur. Sources dans `Documentation/Logo/` (SVG, PNG 1024 et 4096). L'icône de l'Apple TV est en deux
couches — le fond, le billet — pour l'effet de relief au focus (`SeanceTV/Assets.xcassets`).

## 9. Avant de livrer une page

1. Elle n'utilise que les couleurs du tableau, et aucun composant « maison » qui double un composant de la liste.
2. Elle a été regardée en apparence sombre **et** claire, et en texte agrandi (`TourCompletTests`).
3. Sur l'iPad : en portrait et en paysage (`IPadTests`).
4. Son état vide a été regardé (`EtatsVidesTests`, `SEANCE_DEMO=vide`).
5. `AccessibiliteTests` passe.

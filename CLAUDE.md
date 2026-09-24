# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Séance est une app personnelle (iPhone, iPad, Mac par Mac Catalyst, Apple TV) pour les films et séries : où regarder en Suisse, suivi des épisodes, programmes TV, NAS, « Qu'est-ce que je regarde ce soir ? ». Tout le dépôt est en français : identifiants Swift, commentaires, scripts, messages de commit. Garder cette langue, accents compris dans les textes (pas dans les identifiants).

## Commandes

```sh
outils/verifier.sh            # tout avant un commit : SeanceKit, SeanceDonnees, interface iPhone puis iPad (10 à 15 min)
outils/verifier.sh --rapide   # sans les tests d'interface (une minute)

outils/tester.sh                              # tests de SeanceKit avec les seuls Command Line Tools
outils/tester.sh --filter "Fusion"            # une suite ou un test (arguments passés à `swift test`)
(cd SeanceDonnees && xcodebuild test -scheme SeanceDonnees -destination 'platform=macOS')   # @Model exige Xcode

outils/tests-interface.sh                                  # tests d'interface sans clé, simulateur iPhone 17 Pro
outils/tests-interface.sh TourCompletTests/testGrandTexte  # un seul (Classe ou Classe/test, plusieurs possibles)
SIMULATEUR="iPad Air 11-inch (M4)" outils/tests-interface.sh IPadTests
RESULTAT=.build/x.xcresult outils/tests-interface.sh …     # où ranger le résultat ; journal : .build/tests-interface.log

outils/generer-projet.sh      # régénère Seance.xcodeproj (XcodeGen, téléchargé dans outils/.bin)
outils/installer.sh           # Release sur iPhone, iPad, Apple TV et Mac ; ou --iphone, --ipad, --mac, --tv
outils/captures.sh            # captures du simulateur dans .build/captures (captures-tv.sh pour l'Apple TV)
```

- `Seance.xcodeproj` est **généré** : modifier `project.yml`, jamais le projet, et relancer `outils/generer-projet.sh` après tout nouveau fichier ou changement de cible.
- Homebrew est installé (ffmpeg, ffprobe dans `/opt/homebrew/bin`) ; pas de linter. Swift 6, concurrence stricte (`SWIFT_STRICT_CONCURRENCY: complete`), iOS/tvOS/macOS 26.
- Les tests unitaires utilisent Swift Testing (`@Suite`, `@Test`), les tests d'interface XCTest. Les suites « réelles » (TMDB, guide TV, NAS) ne s'activent qu'avec une clé ou un accès dans l'environnement.
- Un test d'interface **sauté** donne quand même « TEST SUCCEEDED » : lire les tests exécutés, pas le verdict (`verifier.sh` refuse les tests sautés).

## Architecture

Trois paquets Swift locaux, en couches, partagés par toutes les cibles :

- **`SeanceKit`** — le moteur, sans persistance ni dépendance externe : client TMDB et cache, critères d'Explorer, guide TV (XMLTV, gzip) et rattachement à TMDB, profil de goûts et recommandation (client Claude facultatif, classement local sinon), analyse des noms de fichiers du NAS, format de sauvegarde et fusion de synchronisation, trousseau. Tout accès réseau passe par le protocole `TransportHTTP` (`URLSession` en vrai, simulé dans les tests avec les réponses de `Tests/SeanceKitTests/Fixtures`).
- **`SeanceDonnees`** — le modèle SwiftData et les services qui appliquent le moteur au magasin (`ServiceSuivi`, `ServiceSoiree`, `ServiceSynchro`, `ServiceSauvegarde`…). Deux configurations locales, « Utilisateur » et « Cache », **sans CloudKit** (compte Apple gratuit) ; `EntrepotSeance.conteneur(_:)` ouvre le magasin dans l'App Group `group.ch.patrick.seance`, que le widget partage.
- **`SeanceNAS`** — accès SMB (AMSMB2), séparé pour que le moteur reste sans dépendance.

Cibles (`project.yml`) :

- **`Seance/`** — l'app iOS / iPadOS / Mac Catalyst. `Etat/` contient l'état `@Observable` : `EtatApp` (clients TMDB et Claude, présents seulement si une clé est au trousseau ; demandes de navigation entre écrans comme `ongletDemande`, `ficheDemandee`) et ses sous-états (`EtatNAS`, `EtatAlertes`, `EtatSynchro`, `EtatOu`, `EtatDecors`). `ConteneurApp` ouvre le magasin une seule fois, pour l'interface, Siri et les raccourcis. `Ecrans/` a un dossier par écran, `Design/` le thème et les composants communs.
- **`SeanceWidget/`** — l'extension ; `SeanceWidget/Partage` est aussi compilé dans l'app (aperçu des widgets, ✓ des épisodes).
- **`SeanceTV/`** — interface tvOS à part, volontairement petite (`EtatTV`) ; elle réutilise `Seance/Design/Theme.swift`, `Demonstration.swift` et `FauxTMDB.swift` par `project.yml`.
- **`SeanceUITests/`** — tests d'interface de l'app iOS.

### Démonstration et faux TMDB

Les tests d'interface et les captures tournent sans clé ni réseau : `Lancement.demonstration(app)` pose `SEANCE_DEMO=1` (magasin en mémoire rempli par `Seance/Etat/Demonstration.swift` ; `SEANCE_DEMO=vide` pour les états vides) et `SEANCE_FAUX_TMDB=<dossier>` (`FauxTMDB`, DEBUG seulement, rejoue les fixtures de SeanceKit lues sur le disque du Mac). Le faux TMDB n'a qu'une fiche film et une fiche série : bon pour la mise en page, pas pour les contenus. La démonstration efface les `UserDefaults`, dans le simulateur seulement — ne pas la lancer sur le Mac, l'identifiant est celui de la vraie app. Une clé réelle se passe par `SEANCE_CLE_TMDB` (ou `outils/.cle-tmdb`, ignoré par git), jamais dans le code.

Un test d'interface ne doit pas dépendre de l'heure : le guide télé fictif a des heures fixes « ce soir », ce qui doit être « à venir » se teste sur Demain. Dans les grilles paresseuses, utiliser `app.amener(element)` plutôt que `swipeUp`.

## Charte 8.0 — prérequis de toute interface

Toute page, sur tous les appareils, **et** tout ce qui porte le nom de Séance hors de l'app (widgets, notifications, e-mail de la semaine, étagère de l'Apple TV) suit la charte validée le 24.09.2026. Les maquettes font foi : `Documentation/Maquette — charte commune.png` et `Maquette — Séance 7, iPhone / iPad et Mac / Apple TV.png` (sources `.build/charte/`). Une interface qui s'en écarte n'est pas terminée.

- **Sombre seulement** : les couleurs viennent des jetons de `Theme`, jamais en dur (`Color(red:…)`, `.system(size:)` interdits dans les vues) ; plus d'apparence claire.
- **L'orange est réservé à ce qui se touche** : bouton principal, liens, onglet choisi, interrupteurs. Dates, lignes d'origine, badges, barres de statistiques : blanc ou gris. Vert = vu, en ordre ; rouge = retirer, en direct.
- **Texte** : styles du système (Dynamic Type) sur l'iPhone et l'iPad, tailles de tvOS sur la TV.
- **Icônes** : SF Symbols seulement, une graisse (demi-gras), une couleur ; contour au repos, plein quand c'est choisi. Pas d'emoji dans l'interface. Les logos des plateformes ne servent qu'à dire « où ».
- **Un seul bouton principal par écran**, qui dit ce qu'il fait (« Regarder sur Prime Video », « Reprendre à 1:03:12 ») ; le reste en boutons secondaires gris ou en liens. Sur la TV, le focus est blanc et soulève l'élément.
- **Navigation** : trois onglets partout — Accueil · Regarder · Mes listes — et la loupe. Le portrait en haut à gauche (qui regarde, Préférences), **la roue des réglages en haut à droite de chaque page**, une seule par page.
- **Regarder** = la rangée de jours (première tuile « Auj. », jamais « Ce soir ») + Tout · Streaming · TV · NAS. Un autre jour sert à planifier.
- **Composants communs** à l'app et à la TV, qui ne changent que de taille : carte 16/9 (ligne d'origine, titre, faits, ▶︎ blanc — ni badge, ni étoile, ni rangée de logos), bouton principal, rangée de jours, en-tête de section (un titre et « Tout voir », sans phrase dessous), ligne « Où regarder ». La fiche garde partout le même ordre : image, titre et faits, action principale, Ma liste · Ce soir · ⋯, ton avis, où regarder, résumé, épisodes, casting.
- **Gestes nommés** : glisser et appui long (clic droit sur le Mac, appui long à la télécommande) montrent les mêmes actions, dans les mêmes mots ; retour au toucher sur les actions (Terminé, Ma liste).
- **Vocabulaire** : « Suggestions » (jamais « Idées »), « Ma liste », « Ce soir », « Terminé », « Me prévenir », « TV ». Les explications sont derrière « ⓘ », pas sous les titres.
- **Vérifiée par les tests** : `CharteTests` (SeanceKit, lit les sources de l'app, de la TV et des widgets) refuse une couleur en dur hors des thèmes (`Theme.swift`, `ModelesWidgets.swift`, les cartes image de `BilanAnneeView`), une taille de texte en dur sur l'iPhone, l'iPad et les widgets (une icône proportionnelle à son cercle reste permise ; la TV garde ses tailles tvOS), tout emoji affiché et l'ancien vocabulaire (« Idées », « Télé »), comme `AccessibiliteTests` refuse une zone de toucher trop petite. Composants communs : `Seance/Design/Charte.swift` (`SelecteurPuces`, `PuceCharte`, `StyleBoutonPrincipal/Secondaire/Rond`, `EnTeteSection`, `titrePage`), `BoutonRondTV` sur la TV.

## Règles propres au projet

- **Navigation par valeur uniquement** : `NavigationLink(value:)`, avec les destinations déclarées à la racine de chaque pile par `destinationsTitres()` (`RacineView.swift` : `ReferenceTitre`, `ReferencePersonne`, `DestinationReglage`). Jamais `NavigationLink { Vue() }` ni `navigationDestination(isPresented:)` : un lien « par vue » a figé l'app sur l'iPhone.
- **Tout changement d'un `@Model`** passe par un nouveau `VersionedSchema` dans `SeanceDonnees/…/SchemaSeance.swift` (la marche à suivre est en tête du fichier) : recopier l'ancienne classe dans la version courante, créer la version suivante, ajouter l'étape au plan, compléter `EntrepotSeanceTests`.
- **Le format de sauvegarde et de synchronisation reste additif** (champs optionnels). La synchronisation passe par un dossier partagé, un fichier par appareil : un dossier d'iCloud Drive, et le dossier « Séance » du NAS en SMB — le seul que l'Apple TV atteigne (`TransportSynchro`, `MoteurSynchro` commun à l'app et à la TV, `DossierSynchroSMB`) ; les suppressions se propagent par comparaison d'états (`FusionSynchro.swift`, `ServiceSynchro.swift`), sans changer le schéma. Les clés (TMDB, Claude, NAS) ne voyagent jamais.
- **👍 👎** : « J'aime » est un `TitreAime` (schéma version 3), hors des listes ; « Je n'aime pas » est un `Suivi` de statut `.exclu` (`ServiceGouts.aimer / jamais / reproposer`). Les deux nourrissent le profil de goûts ; passer les genres à `jamais` quand on les a.
- **E-mail de la semaine** : `LettreHebdo`, `MessageMail`, `ClientSMTP` (SeanceKit/Lettre, TLS implicite port 465 seulement) ; `EtatLettre` l'envoie à l'ouverture ou au réveil en fond après l'échéance, depuis l'appareil — pas de serveur. `SEANCE_SMTP_ESSAI=1 swift test --filter SMTPReel` éprouve la conversation sans identifiants. Depuis la 6.5 : `EtatLettre.Rubrique` (six rubriques cochables), `jours: Set<Int>` (plusieurs envois par semaine, `joursRetenus` gère l'ancien `jour`), `plateformes` et `chaines` pour filtrer les nouveautés et les passages. Le mot de passe SMTP voyage **par le transfert chiffré** (`ConfigurationTransferee.smtp` / `.motDePasseSMTP`), jamais par la sauvegarde ni la synchronisation.
- **Lire tous les formats (6.5)** : `LecteurVLC` (VLCKit, `#if !targetEnvironment(macCatalyst)`) prend le relais d'`AVFoundation` pour AVI, WMV, MKV, DV, MJPEG. Le binaire vient de `outils/telecharger-vlckit.sh` dans `.build/vlckit/` (hors git, 2,7 Go) et n'a **pas** de tranche Mac Catalyst : une tranche vide y est ajoutée pour que le Mac lie sans erreur, où Séance garde le lecteur d'Apple. Les fichiers du NAS se convertissent avec `outils/analyser-videos.sh` puis `outils/convertir-videos.sh` (libx264 CRF 18 pour le DV et le MJPEG, CRF 20 plafonné au débit source pour ce qui est déjà compressé ; `-nostdin` obligatoire, sinon ffmpeg vole l'entrée de la boucle).
- **Famille (6.0)** : un magasin « Utilisateur » par profil (`EntrepotSeance.Emplacement.profil`, registre `ProfilsFamille` dans les réglages du groupe d'apps), cache commun, aucun changement de schéma. `ConteneurApp.changerDeProfil` rouvre le magasin, recopie le foyer (plateformes, chaînes) et prévient l'app, qui recrée `EtatApp` et ses écrans. Tout ce qui garde un repère par appareil doit être pensé par profil (`EtatSynchro` : espace, état, sous-dossier).
- **« Vu avec qui ? » (6.1)** : un visionnage s'inscrit directement chez d'autres profils (`VuEnsemble`, `ConteneurApp.conteneur(de:)`), puis `EtatSynchro(profil:).synchroniser(…, pourUnAutre: true)` dépose leur sous-dossier sans lire ni appliquer les réglages de cet appareil (on redépose ceux de leur dernier état connu).
- **Liens directs (6.1)** : `ReserveIdentifiants` (SeanceKit) lit sur Wikidata, sans clé, les identifiants Netflix, Apple TV et Disney+ d'un titre (en lot, gardés 30 jours) ; `LiensPlateformes.lien(plateforme:titre:reference:identifiants:)` ouvre le titre, sinon la recherche. Prime Video reste en recherche (références d'Amazon.com). `LiensChaines.blueTV` ouvre une chaîne en direct dans blue TV (numéros tirés de la liste publique de Swisscom ; `CatalogueBlueTV` donne l'émission en cours, `tvguide://` ouvre l'app). Rien de personnel dans ces requêtes ; pas de réseau en démonstration. `SEANCE_WIKIDATA_REEL=1` active le test réel. Tout lancement passe par `LancementPlateforme` / `LancementBlueTV` (6.3) : sablier `EtatApp.ouverture` posé à la racine, attente de Wikidata bornée à 2,5 s puis recherche.
- **Vidéos personnelles (6.2)** : des albums de souvenirs (`ArbreVideosPerso.albums`, `AlbumSouvenirs`) — un dossier d'événement est un album, une vidéo seule (racine ou dossier d'année) fait carte à elle seule ; icône proposée d'après le nom (`IconesSouvenirs`), couverture choisie (`CouverturesSouvenirs`, clé `videos.couvertures`, datée entrée par entrée, voyage dans les réglages synchronisés). Le lecteur intégré surveille qu'une vidéo démarre vraiment, sinon elle part dans Infuse ou VLC ; il déclare la session audio `.playback` (sinon le commutateur silencieux coupe le son) et nomme le codec fautif (`LecteurIntegre.codec`). Sur la page NAS, « Perso » est un rayon du sélecteur (`VideosPersoView(integree: true)`).
- **Bibliothèque du NAS (6.4)** : la page utilise `CarteLargeTitre` (donc le ▶︎ et les logos), et se range par `RangementNAS` — A→Z, ajouts, année, genre (`TrancheNAS.ranger`). La date d'ajout et les genres ne sont **pas** dans SwiftData : `DetailsNAS` (SeanceKit) les garde dans les réglages (`nas.details`), écrits par `ServiceBibliotheque` — le cache NAS est effacé et refait à chaque analyse, une version de schéma pour ces deux champs faisait échouer les migrations (`configurationSchemaNotFoundInContainerSchema`).
- **Vignettes des souvenirs (6.4)** : `VignettesSouvenirs` tire la première image d'une vidéo personnelle (AVAssetImageGenerator à travers `RelaisVideo`, deux à la fois), la garde dans les caches de l'appareil, et la pose sur `CarteLargeTitre(vignette:)` / `CarteLargeTV(vignette:)`. Seuls mp4, m4v et mov en donnent une.
- **Terminés** : une série passe seule dans Terminés quand elle est finie chez TMDB et que son dernier épisode est vu (`ProgressionSerie.estTerminee`, `ServiceSuivi.rangerSiTerminee`) ; la liste se range par mois (`TerminesParMois`).
- **Centrale de la maison** (`EtatCentrale`, Mac seulement) : passage tous les quarts d'heure, `beginActivity` contre la veille, `SMAppService` pour l'ouverture de session.
- **Apple TV, les mêmes informations que l'iPhone (6.3)** : `EtatOu` et les notes de version (`Seance/Ecrans/Reglages/Versions.swift`) sont compilés dans la cible TV par `project.yml` — les logos des plateformes sur les cartes (`BadgeOuTV`) et Réglages › À propos › Versions (`PageVersionsTV`) en viennent. Toute question se pose avec `DialogueTV` ; `alert` et `confirmationDialog` écrivent blanc sur blanc sur tvOS.
- **Tests de l'Apple TV** : `SeanceTVUITests` (XCUIRemote), lancés par `outils/verifier.sh`. Une pile dont le chemin est typé (`[ReferenceTitre]`) refuse en silence toute autre destination : utiliser `NavigationPath`.
- **Navigation 8.0** : trois onglets partout — `accueil`, `regarder`, `listes` — et la recherche (`explorer`). `ceSoir`, `streaming`, `tele`, `nas` sont des demandes que `RacineView.aller(a:)` traduit en Regarder sur la bonne source (`etat.sourceRegarder`, `etat.jourRegarder`) ; `profil` et `reglages` ouvrent leur feuille (Réglages en deux colonnes sur l'iPad et le Mac). `boutonBarreLaterale()` pose le portrait et la roue ; `destinationsTitres()` met la roue sur les pages ouvertes. Regarder : `Seance/Ecrans/Sources/Sources.swift` (`RegarderView`, `SoireeView` pour « Tout », `ProgrammeTeleView(jourImpose:)`, les filtres d'Explorer par `ExplorerModele`) ; `RegarderTV` et ses `Sections…TV` sur la TV, `ExplorerTV(sourceImposee:)` pour les filtres en deux parties. Les tests d'interface passent par `app.aller("Ce soir" | "TV" | "Explorer"…)`, `app.ouvrirPreferences()`, `app.ouvrirReglages()`. On écrit « TV », jamais « Télé ». Réglages en liste groupée (`LigneReglage`).
- **Lecteur de l'iPhone (7.0, 8.0)** : `LecteurVLC` lit le NAS en SMB directement (`:smb-user`, `:smb-pwd`), le relais HTTP en secours ; `EtatNAS.dansSeance` (par défaut) ou Infuse, dans Réglages › Lecture ; `OrientationLecture` et `DelegueApp` laissent tourner l'iPhone le temps du lecteur. Depuis la 8.0, films, séries et souvenirs passent par `etat.lecture` (`LectureEnCours`), posé par la racine **par-dessus l'app** et non en feuille : « Continuer dans Séance » démarre l'image dans l'image de VLCKit (`VueImageDansLImage`, `ControleurImage`, `UIBackgroundModes: audio`) et le lecteur s'efface sans s'arrêter ; la croix ferme. Le Mac garde le lecteur d'Apple.
- **Reprendre (8.0)** : `PositionsLecture` (SeanceKit, clé `lecture.positions`) retient la position de chaque vidéo du NAS par chemin, voyage dans les réglages synchronisés (la plus récente l'emporte, comme les couvertures ; la TV la dépose aussi), et nourrit « Reprendre à … » sur la fiche, la rangée « Reprendre » de l'accueil et l'étagère de l'Apple TV. `EtatNAS.positions`, `EtatTV.positions`.
- **Charte graphique** : `Documentation/Charte graphique.md` dit quel composant utiliser pour quoi (couleurs de `Theme`, `SelecteurCases` pour choisir ce que la page montre, `TuileReglage`, `EtatVide`, `BoutonTV`…). Pas de composant « maison » qui double un composant de la charte, pas d'icônes multicolores, pas de contrôle segmenté hors des formulaires de réglage.
- **Accessibilité** : `AccessibiliteTests` est bloquant (descriptions, zones de toucher de 44 points) ; utiliser `BasculeGrilleListe` et `.zoneDeToucher()` de `Seance/Design/`.
- Sur l'iPad, toute interface se vérifie en portrait **et** en paysage (`IPadTests`) ; le Mac s'appuie sur l'interface iPad.
- Les exigences sont numérotées (EF-…, UX-…) et citées dans les commentaires ; le cahier des exigences est dans `Documentation/` (non suivi par git, mis à jour sur demande seulement).

## Déroulement d'une version

Chaque lot de travail devient une version : `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` dans `project.yml`, notes en tête de `Seance/Ecrans/Reglages/Versions.swift` (les deux numéros doivent correspondre), `outils/generer-projet.sh`, `outils/verifier.sh`, `outils/installer.sh`, puis un commit « Séance X.Y : … » (ligne vide après le sujet) sur `main`. Avec le compte Apple gratuit, l'app installée expire au bout de 7 jours : `outils/installer.sh` la réinstalle, les données restent sur l'appareil.

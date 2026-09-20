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
SIMULATEUR="iPad Air 11-inch (M3)" outils/tests-interface.sh IPadTests
RESULTAT=.build/x.xcresult outils/tests-interface.sh …     # où ranger le résultat ; journal : .build/tests-interface.log

outils/generer-projet.sh      # régénère Seance.xcodeproj (XcodeGen, téléchargé dans outils/.bin)
outils/installer.sh           # Release sur iPhone, iPad, Apple TV et Mac ; ou --iphone, --ipad, --mac, --tv
outils/captures.sh            # captures du simulateur dans .build/captures (captures-tv.sh pour l'Apple TV)
```

- `Seance.xcodeproj` est **généré** : modifier `project.yml`, jamais le projet, et relancer `outils/generer-projet.sh` après tout nouveau fichier ou changement de cible.
- Pas de Homebrew sur ce Mac ; pas de linter. Swift 6, concurrence stricte (`SWIFT_STRICT_CONCURRENCY: complete`), iOS/tvOS/macOS 26.
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

## Règles propres au projet

- **Navigation par valeur uniquement** : `NavigationLink(value:)`, avec les destinations déclarées à la racine de chaque pile par `destinationsTitres()` (`RacineView.swift` : `ReferenceTitre`, `ReferencePersonne`, `DestinationReglage`). Jamais `NavigationLink { Vue() }` ni `navigationDestination(isPresented:)` : un lien « par vue » a figé l'app sur l'iPhone.
- **Tout changement d'un `@Model`** passe par un nouveau `VersionedSchema` dans `SeanceDonnees/…/SchemaSeance.swift` (la marche à suivre est en tête du fichier) : recopier l'ancienne classe dans la version courante, créer la version suivante, ajouter l'étape au plan, compléter `EntrepotSeanceTests`.
- **Le format de sauvegarde et de synchronisation reste additif** (champs optionnels). La synchronisation passe par un dossier d'iCloud Drive, un fichier par appareil ; les suppressions se propagent par comparaison d'états (`FusionSynchro.swift`, `ServiceSynchro.swift`), sans changer le schéma. Les clés (TMDB, Claude, NAS) ne voyagent jamais.
- **Accessibilité** : `AccessibiliteTests` est bloquant (descriptions, zones de toucher de 44 points) ; utiliser `BasculeGrilleListe` et `.zoneDeToucher()` de `Seance/Design/`.
- Sur l'iPad, toute interface se vérifie en portrait **et** en paysage (`IPadTests`) ; le Mac s'appuie sur l'interface iPad.
- Les exigences sont numérotées (EF-…, UX-…) et citées dans les commentaires ; le cahier des exigences est dans `Documentation/` (non suivi par git, mis à jour sur demande seulement).

## Déroulement d'une version

Chaque lot de travail devient une version : `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` dans `project.yml`, notes en tête de `Seance/Ecrans/Reglages/Versions.swift` (les deux numéros doivent correspondre), `outils/generer-projet.sh`, `outils/verifier.sh`, `outils/installer.sh`, puis un commit « Séance X.Y : … » (ligne vide après le sujet) sur `main`. Avec le compte Apple gratuit, l'app installée expire au bout de 7 jours : `outils/installer.sh` la réinstalle, les données restent sur l'appareil.

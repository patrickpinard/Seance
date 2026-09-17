# Séance

App iPhone personnelle pour les films et séries d'action : où regarder en Suisse, suivi des épisodes,
programmes TV, NAS, et « Qu'est-ce que je regarde ce soir ? ».

Le cahier des exigences (EF-01 à EF-80, UX-01 à UX-29, jalons) est un document Claude :
https://claude.ai/code/artifact/2dddc5b3-a9c7-4408-afd3-263d00b99e49

## Organisation

| Dossier | Contenu | Compilation |
| --- | --- | --- |
| `SeanceKit/` | Moteur sans persistance : client TMDB, critères Explorer, programmes TV (XML TV Fr, gzip, XMLTV), rattachement à TMDB, trousseau, profil de goûts et suggestions du soir | Command Line Tools ou Xcode |
| `SeanceDonnees/` | Modèle SwiftData (configurations « Utilisateur » et « Cache ») | Xcode seulement : les macros `@Model` n'existent pas dans les Command Line Tools |
| `Seance/` | App iPhone (écran provisoire du jalon 1) | Xcode |
| `SeanceWidget/` | Widget (vide au jalon 1) | Xcode |
| `project.yml` | Description du projet Xcode pour XcodeGen | — |
| `outils/` | `tester.sh`, `generer-projet.sh`, `installer.sh` | — |

## Avant la première compilation dans Xcode

1. Accepter la licence d'Xcode 27, dans le Terminal : `sudo xcodebuild -license accept`.
2. Ouvrir `Seance.xcodeproj`, puis dans Signing & Capabilities choisir l'équipe personnelle
   (compte Apple gratuit) pour les cibles `Seance` et `SeanceWidget`.
3. Si Xcode refuse l'identifiant `ch.patrick.seance` (déjà pris), le remplacer dans `project.yml`,
   ainsi que le groupe `group.ch.patrick.seance`, puis relancer `outils/generer-projet.sh`.

Avec un compte gratuit, l'app installée sur l'iPhone cesse de s'ouvrir au bout de 7 jours :
la réinstaller avec `outils/installer.sh`, les données restent sur chaque appareil.

## Commandes

```sh
outils/tester.sh            # tests de SeanceKit, sans Xcode
outils/generer-projet.sh    # régénère Seance.xcodeproj après modification de project.yml
outils/installer.sh         # compile en Release et installe sur l'iPhone branché et dans /Applications du Mac
outils/installer.sh --mac   # ou --iphone : un seul appareil
```

Les tests de `SeanceDonnees` se lancent dans Xcode (schéma du paquet `SeanceDonnees`).

## Sources de données

- TMDB : catalogue, plateformes par pays (données JustWatch), dates. Attribution obligatoire.
- API Claude : classement et explication des suggestions de « Ce soir » (EF-22 à EF-27). Clé facultative :
  sans elle, le classement se fait sur l'iPhone, à partir du profil de goûts.
- XML TV Fr : programmes des chaînes françaises, projet bénévole, un téléchargement par jour après 3 h.
- API SRG SSR EPG : programmes RTS (jalon 2, clé à créer).

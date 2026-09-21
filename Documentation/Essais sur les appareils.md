# Essais sur les vrais appareils

Ce que le simulateur ne peut pas vérifier : iCloud Drive, AirDrop, Siri, Infuse et VLC, les notifications réelles.
Dix à quinze minutes, iPhone, iPad et Mac sous la main. Pour chaque ligne : ce qu'on fait, ce qu'on doit voir.

## 1. Synchronisation par iCloud Drive

1. Sur chaque appareil : Réglages › Sauvegarde et synchronisation › choisir **le même dossier** d'iCloud Drive.
   On doit voir : le nom du dossier, et « Tes données ont été déposées… » après « Synchroniser maintenant ».
2. Dans Fichiers, le dossier contient un fichier par appareil : « Séance — iPhone XXXX.json », « — iPad… », « — Mac… ».
3. **Ajout** — sur l'iPhone, ajoute un film à « À voir ». Ferme et rouvre Séance sur l'iPad.
   On doit voir : le bandeau « Synchronisé : 1 titre (iPhone) », et le film dans Mes listes.
4. **Suppression** — sur l'iPhone, retire ce film de Mes listes. Rouvre Séance sur l'iPad (après une minute, le temps qu'iCloud transporte).
   On doit voir : « 1 supprimé (iPhone) », et le film parti de l'iPad. Il ne doit **pas** revenir sur l'iPhone ensuite.
5. **Retour en arrière** — sur l'iPad, marque un film comme vu avec une note ; laisse synchroniser ; puis sur l'iPhone, « Marquer comme non vu ».
   On doit voir sur l'iPad : le film de nouveau « à voir ».
6. Le prénom changé sur un appareil arrive sur les autres ; l'apparence (clair/sombre), non.

Si rien n'arrive : iCloud Drive n'a peut-être pas encore téléchargé le fichier. Ouvre le dossier dans Fichiers, puis relance.

## 2. AirDrop

1. iPhone : Réglages › Sauvegarde › « Envoyer à un autre appareil… » › AirDrop vers l'iPad.
2. Sur l'iPad, on doit voir « Ouvrir avec Séance », puis « Importer cette sauvegarde ? », puis le bandeau « Importé : … ».
3. Même essai vers un appareil d'un autre compte Apple.

## 3. Siri

Ouvre Séance une fois après l'installation, attends une minute, puis :

- « Dis Siri, qu'est-ce que je regarde ce soir avec Séance ? » → Siri lit ta soirée.
- « Dis Siri, ajoute *un titre de ta liste À voir* à ma soirée dans Séance » → « C'est noté… ».
- « Dis Siri, ajouter à ma soirée avec Séance » → Siri demande le titre.
- Si Siri bute sur « Séance » : essayer « … avec Séance Ciné ».
- App Raccourcis › Raccourcis d'apps : les tuiles « Ce soir » et « Ajouter à ma soirée » doivent y être.

## 4. Lecture du NAS

1. Réglages › Lecture : chaque app dit « Installée » ou « Pas installée sur cet appareil ».
2. Fiche d'une série du NAS › liste « Épisodes » › ▶︎ sur un épisode marqué « NAS ».
   - Infuse : s'ouvre sur l'épisode et lance la lecture. **Condition** : le partage du NAS est ajouté dans Infuse *sur cet appareil*, et indexé.
   - VLC (appui long sur ▶︎ › « Lire avec VLC ») : lit le fichier directement.
3. Noter ce qui se passe si ça échoue : message de Séance, Infuse ouvert sans lecture, ou rien du tout.

## 5. Notifications

1. Programme télé › cloche sur un passage qui commence dans plus d'un quart d'heure → bandeau « Rappel à HH:MM… ».
2. La notification arrive un quart d'heure avant ; la toucher ouvre la fiche.
3. iPhone verrouillé, Apple Watch au poignet : l'alerte doit apparaître sur la montre
   (app Watch › Notifications › Séance coché sous « Recopier les alertes de l'iPhone »).
4. **Depuis la 3.1** — appui long sur l'alerte (iPhone), ou la toucher sur la montre : le bouton « Ajouter à ma soirée ».
   On doit voir, en rouvrant Séance : le titre dans Ce soir, sans que l'app se soit ouverte au moment du toucher.

## 6. Apparence et texte

1. Réglages › Apparence › Clair, sur l'iPad et le Mac : parcourir Accueil, Ce soir, une fiche, Réglages.
2. Réglages d'iOS › Accessibilité › Taille du texte au maximum : l'heure des passages télé, les tuiles de jours et les titres doivent grandir sans se chevaucher.

## 7. Nouvel appareil, sauvegardes datées, iPad (3.1)

1. Réglages › Tes données › **Nouvel appareil** : les trois étapes (données, clé TMDB, mot de passe du NAS) sur un écran ;
   une étape déjà faite est cochée en vert. Le même écran s'ouvre depuis la bienvenue (« J'ai déjà Séance sur un autre appareil »).
2. Après deux ou trois synchronisations avec des changements : dans Fichiers, le dossier choisi contient « Sauvegardes datées »,
   avec au plus cinq fichiers par appareil.
3. iPad (3.1.1) — **en paysage**, au lancement : la barre latérale est ouverte à côté de la page, avec tous les onglets.
   La refermer, quitter Séance, la relancer : elle reste fermée. **En portrait** : l'accueil est visible en entier,
   rien ne le recouvre ; le bouton en haut à gauche ouvre la barre.
4. Explorer : taper un titre de ta liste — la section « Dans tes listes » apparaît avant les résultats de TMDB.

## Synchronisation par le NAS (4.6, EF-144)

Rien de ceci n'a pu être essayé sans ton NAS : le moteur est testé de bout en bout entre deux appareils fictifs
(`MoteurSynchroTests`), pas le transport SMB. Pour l'essayer depuis le Mac, avec un compte qui **écrit** dans le partage :

```sh
SEANCE_NAS_HOTE=… SEANCE_NAS_PARTAGE=Films SEANCE_NAS_UTILISATEUR=… SEANCE_NAS_MOT_DE_PASSE=… \
  swift test --package-path SeanceNAS --filter DossierSynchroSMB
```

1. iPhone, à la maison : Réglages › Sauvegarde › **Par le NAS**. Attendu : « Tes données ont été déposées », et sur le NAS
   un dossier `Séance` à la racine du partage, avec `Séance — iPhone XXXX.json`.
   - « Le NAS refuse… » ou une erreur d'écriture : le compte n'a que la lecture. Lui donner l'écriture sur le partage.
2. Apple TV : ouvrir Séance. Attendu, en bas de l'écran : « Synchronisé avec tes appareils : N changements » ; Mes listes
   et Ce soir sont remplis. Le dossier du NAS contient maintenant `Séance — Apple TV XXXX.json`.
3. Sur la TV, garder un titre « à voir » depuis sa fiche ; quitter l'app. Sur l'iPhone, rouvrir Séance (deux minutes au
   moins après la dernière synchronisation) : le titre arrive dans À voir.
4. Sur l'iPhone, retirer ce titre ; rouvrir Séance sur la TV : il disparaît aussi.
5. Hors de la maison : ouvrir Séance sur l'iPhone. Attendu : aucun message d'erreur ; Réglages › Sauvegarde montre
   discrètement que le NAS n'a pas répondu.
6. iPad et Mac : activer « Par le NAS » aussi, si tu veux qu'ils passent par lui en plus d'iCloud Drive.

## E-mail de la semaine (5.0)

Le client SMTP n'a été éprouvé ici que jusqu'au refus d'un faux mot de passe (`SEANCE_SMTP_ESSAI=1 swift test --filter SMTPReel`
dans `SeanceKit`) : aucun e-mail réel n'est parti.

1. Réglages › E-mail de la semaine : serveur (`smtpauths.bluewin.ch`), port 465, utilisateur, adresse, mot de passe ;
   une ou plusieurs adresses séparées par « ; ».
2. « Voir l'e-mail de cette semaine » : l'aperçu doit montrer tes titres de la semaine, aux couleurs de Séance.
3. « Envoyer un e-mail d'essai ». Attendu : « E-mail d'essai envoyé à … », et l'e-mail dans la boîte (voir aussi les indésirables).
   - « Le serveur refuse l'utilisateur ou le mot de passe » : Gmail exige un mot de passe d'application.
   - Un serveur en port 587 seulement (iCloud) ne convient pas.
4. Activer l'envoi, choisir le jour et l'heure : l'e-mail part à la première ouverture de Séance après ce moment.
5. Les réglages arrivent sur les autres appareils par la synchronisation — pas le mot de passe.

## Alertes sur l'Apple Watch (5.1)

iOS ne transmet une alerte à la montre que si l'iPhone est verrouillé ou en veille.

1. Réglages › Alertes › **Tester sur l'Apple Watch**, puis verrouiller l'iPhone ; montre au poignet, déverrouillée.
   Attendu, vingt secondes plus tard : l'alerte au poignet.
2. Rien au poignet : la section « Apple Watch » signale ce qui bloque dans les réglages de notification de Séance. Sinon :
   app Watch › Notifications › « Recopier les alertes de l'iPhone » › Séance ; et aucun mode de concentration actif.
3. Depuis l'Apple TV : Réglages › « Tester une alerte », ouvrir Séance sur l'iPhone, le verrouiller : l'alerte arrive vingt
   secondes après la synchronisation.



## Famille et centrale de la maison (6.0)

1. Réglages › Famille › **Ajouter une personne**, puis « Choisir » : l'app se reconstruit, ses listes sont vides, les plateformes et
   les chaînes sont celles de la maison. Revenir au profil principal : tout est là.
2. Fermer et rouvrir Séance : « Qui regarde ? » s'affiche.
3. Ce soir › Ajouter : cocher l'autre personne sous « Qui regarde ce soir ? » ; les idées changent.
4. Même prénom créé sur l'iPad : après une synchronisation de chaque côté, ses listes s'y retrouvent (sous-dossier `Famille/Prénom`).
5. Mac : Réglages › **Centrale de la maison**, activer les deux interrupteurs, laisser Séance ouverte. Attendu : « Dernier passage »
   avance tous les quarts d'heure ; le Mac ne se met plus en veille ; après redémarrage, Séance s'ouvre seule. `caffeinate` devient inutile.
6. Spotlight : taper le nom d'un titre de tes listes ; le toucher ouvre sa fiche.
\n
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
3. iPad : au lancement, la barre latérale est ouverte et montre tous les onglets.
4. Explorer : taper un titre de ta liste — la section « Dans tes listes » apparaît avant les résultats de TMDB.


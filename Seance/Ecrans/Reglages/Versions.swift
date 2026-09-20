import SwiftUI

/// Une version de Séance et ce qu'elle apporte, vu de haut. La plus récente en premier ;
/// son numéro doit correspondre à `MARKETING_VERSION` dans `project.yml`.
struct NoteVersion: Identifiable {
    struct Fonctionnalite: Identifiable {
        let symbole: String
        let titre: String
        let detail: String

        var id: String { titre }
    }

    let numero: String
    let date: String
    let resume: String
    let fonctionnalites: [Fonctionnalite]

    var id: String { numero }

    static let historique: [NoteVersion] = [
        NoteVersion(
            numero: "4.2",
            date: "20 septembre 2026",
            resume: "Un nouvel iPad ou un Mac se configure comme l'Apple TV, par un code ; et ta soirée s'affiche sur l'écran d'accueil de la TV.",
            fonctionnalites: [
                Fonctionnalite(symbole: "iphone.and.arrow.forward", titre: "Tout recevoir par un code",
                               detail: "« Nouvel appareil » propose d'abord le plus simple : cet appareil affiche un code, et un autre — Réglages › Tes appareils › « Envoyer à un appareil » — lui envoie tout d'un coup, clé TMDB et NAS compris, ce qu'aucun fichier de sauvegarde ne porte."),
                Fonctionnalite(symbole: "appletv", titre: "Apple TV : l'étagère du haut",
                               detail: "Place Séance dans la rangée du haut de l'écran d'accueil de l'Apple TV : ta soirée et les nouveautés de ton NAS s'y affichent en affiches, et en choisir une ouvre sa fiche."),
            ]
        ),
        NoteVersion(
            numero: "4.1",
            date: "20 septembre 2026",
            resume: "Des Réglages refaits, un seul lecteur pour « Lire », et une Apple TV presque aussi complète que l'iPhone.",
            fonctionnalites: [
                Fonctionnalite(symbole: "gearshape.2", titre: "Réglages, plus simples",
                               detail: "L'état en tête est la seule entrée de ce qu'il surveille — TMDB, plateformes, télévision, NAS, lecture, alertes, sauvegarde : chaque ligne s'ouvre. Dessous, le reste en tuiles, aux couleurs de Séance. Plus aucun réglage en double."),
                Fonctionnalite(symbole: "play.circle", titre: "Un seul lecteur",
                               detail: "« Lire » ouvre l'app choisie dans Réglages › Lecture, Infuse ou VLC, et elle seule : plus de second bouton ni d'appui long. Ce choix part aussi vers l'Apple TV avec le reste."),
                Fonctionnalite(symbole: "appletv.fill", titre: "Apple TV : tout le reste",
                               detail: "Le programme télé jour par jour et « Ce soir à la télé » sur l'accueil, Explorer par choix plutôt qu'au clavier, ton Profil, une grande image en tête d'accueil, et « Tu l'as regardé ? » au retour d'un film. Les onglets passent dans une barre latérale."),
                Fonctionnalite(symbole: "slider.horizontal.3", titre: "Apple TV : des Réglages complets",
                               detail: "Même page qu'ici, et tout s'y modifie à la télécommande : plateformes, chaînes, goûts, NAS, lecteur. Tant que la synchronisation par le NAS n'est pas là, ces changements restent sur la TV."),
            ]
        ),
        NoteVersion(
            numero: "4.0",
            date: "20 septembre 2026",
            resume: "Séance arrive sur l'Apple TV, et ton iPhone la met en route avec un simple code.",
            fonctionnalites: [
                Fonctionnalite(symbole: "appletv.fill", titre: "Séance sur Apple TV",
                               detail: "Une app à part, faite pour la télécommande : accueil, Ce soir, Mes listes, ta bibliothèque du NAS en grandes affiches, et la fiche d'un titre avec « Lire avec Infuse », Ce soir, À voir, Marquer vu."),
                Fonctionnalite(symbole: "iphone.and.arrow.forward", titre: "Configurer mon Apple TV",
                               detail: "Réglages › Tes données. La TV affiche un code à six chiffres, tu le tapes ici, et tout y arrive par le Wi-Fi de la maison : ta clé TMDB, ton NAS et son mot de passe, tes listes, tes soirées, ce que tu as vu, tes plateformes. Chiffré avec le code, jamais écrit dans un fichier, jamais par internet."),
                Fonctionnalite(symbole: "arrow.triangle.2.circlepath", titre: "Pour mettre la TV à jour",
                               detail: "Refais la même manœuvre : l'envoi complète ce que la TV connaît déjà, sans rien effacer. La synchronisation automatique par le NAS viendra ensuite."),
            ]
        ),
        NoteVersion(
            numero: "3.2.1",
            date: "19 septembre 2026",
            resume: "Sur l'iPad, la barre latérale s'ouvre aussi quand tu tournes la tablette.",
            fonctionnalites: [
                Fonctionnalite(symbole: "rotate.right", titre: "iPad : portrait, puis paysage",
                               detail: "Lancée en portrait puis tournée, Séance ouvre la barre latérale à côté de la page, une fois par session ; ensuite elle est à toi."),
                Fonctionnalite(symbole: "sun.max", titre: "Apparence claire vérifiée sur grand écran",
                               detail: "Accueil, Réglages, Ce soir, Mes listes et Profil relus en clair sur un iPad en paysage."),
            ]
        ),
        NoteVersion(
            numero: "3.2",
            date: "19 septembre 2026",
            resume: "Des pages vides qui expliquent et proposent, des boutons plus faciles à toucher, et un programme télé juste au petit matin.",
            fonctionnalites: [
                Fonctionnalite(symbole: "bookmark", titre: "Mes listes, quand il n'y a encore rien",
                               detail: "Chaque onglet vide dit ce qu'il montrera et comment le remplir, avec un bouton vers Explorer ; le filtre et le tri ne s'affichent plus au-dessus d'une liste vide."),
                Fonctionnalite(symbole: "tv", titre: "Programme télé",
                               detail: "Entre 6 h et la fin d'un film commencé avant 6 h, la page s'ouvrait sur « hier » : une émission en cours se range maintenant dans la journée en cours. Un programme vide propose « Choisir mes chaînes », ou « Toutes les chaînes » si un filtre le vide."),
                Fonctionnalite(symbole: "hand.tap", titre: "Des boutons à la taille du doigt",
                               detail: "Grille ou liste, le tri, « Acteurs suivis » : ils répondaient sur 15 points, ils répondent sur 44. Le même choix grille ou liste partout."),
                Fonctionnalite(symbole: "accessibility", titre: "VoiceOver vérifié à chaque version",
                               detail: "Un audit automatique parcourt l'accueil, Ce soir, Mes listes, À venir, Profil et Réglages : aucun élément sans nom, aucune cible trop petite."),
            ]
        ),
        NoteVersion(
            numero: "3.1.1",
            date: "18 septembre 2026",
            resume: "Sur l'iPad, la barre latérale ne recouvre plus l'accueil.",
            fonctionnalites: [
                Fonctionnalite(symbole: "sidebar.left", titre: "iPad : la barre latérale à sa place",
                               detail: "En paysage, elle s'ouvre à côté de la page et montre tous les onglets ; si tu la refermes, elle le reste. En portrait, où elle recouvrait l'accueil à chaque lancement, elle ne s'ouvre plus toute seule : le bouton en haut à gauche la montre."),
                Fonctionnalite(symbole: "text.alignleft", titre: "Titres sur deux lignes",
                               detail: "Sous les affiches de Mes listes et des listes nommées : « John Wick : Chapitre 2 » et « Chapitre 4 » se distinguent."),
                Fonctionnalite(symbole: "tv", titre: "Programme télé : le compte du jour",
                               detail: "« 3 titres » quand la journée mêle films et séries, au lieu de ne compter que les films."),
            ]
        ),
        NoteVersion(
            numero: "3.1",
            date: "18 septembre 2026",
            resume: "Un nouvel appareil prêt en trois étapes, des alertes à bouton, et les derniers écrans alignés.",
            fonctionnalites: [
                Fonctionnalite(symbole: "iphone.and.arrow.forward", titre: "Nouvel appareil",
                               detail: "Sur l'écran de bienvenue (« J'ai déjà Séance sur un autre appareil ») et dans Réglages : reprendre tes données, saisir ta clé TMDB et le mot de passe du NAS, sur un seul écran."),
                Fonctionnalite(symbole: "bell.badge", titre: "« Ajouter à ma soirée » depuis une alerte",
                               detail: "Un appui long sur une alerte — ou un toucher sur l'Apple Watch — ajoute le titre à ta soirée, sans ouvrir l'app."),
                Fonctionnalite(symbole: "tv", titre: "Programme télé : chaînes et semaine",
                               detail: "Un filtre par chaîne, en haut à droite, et sept jours au lieu de tout le guide."),
                Fonctionnalite(symbole: "square.grid.2x2", titre: "Listes nommées et acteurs en affiches",
                               detail: "Une liste nommée s'ouvre en grille et se partage en texte ; la filmographie d'un acteur passe en affiches, avec le choix de la liste."),
                Fonctionnalite(symbole: "magnifyingglass", titre: "« Dans tes listes »",
                               detail: "Une recherche dans Explorer commence par ce que tu as déjà, sans attendre TMDB."),
                Fonctionnalite(symbole: "dice", titre: "Surprends-moi",
                               detail: "Dans Ce soir : un titre tiré au sort parmi ceux de ta liste que tu peux regarder ce soir. Annulable."),
                Fonctionnalite(symbole: "sidebar.left", titre: "iPad : tous les onglets",
                               detail: "La barre latérale s'ouvre au lancement : Profil et Réglages ne se cachent plus derrière « > »."),
                Fonctionnalite(symbole: "clock.arrow.circlepath", titre: "Sauvegardes datées",
                               detail: "Le dossier de synchronisation garde les cinq derniers états de chaque appareil. Et un enregistrement qui échoue s'écrit désormais au journal au lieu de passer inaperçu."),
            ]
        ),
        NoteVersion(
            numero: "3.0",
            date: "18 septembre 2026",
            resume: "Une synchronisation qui propage aussi les suppressions, l'app utilisable sans réseau, et trois attentions du quotidien.",
            fonctionnalites: [
                Fonctionnalite(symbole: "arrow.triangle.2.circlepath", titre: "Synchronisation complète",
                               detail: "Ce que tu supprimes, marques « non vu » ou changes de note sur un appareil arrive sur les autres : le changement le plus récent l'emporte, et un titre retiré ne revient plus. Ton prénom, tes alertes et l'adresse du NAS suivent aussi. Une sauvegarde importée à la main, elle, ne supprime jamais rien."),
                Fonctionnalite(symbole: "bolt.horizontal", titre: "Plus rapide, et sans réseau",
                               detail: "Les réponses de TMDB sont gardées sur l'appareil : une fiche déjà ouverte s'affiche aussitôt, et dans le train l'app montre ce qu'elle a déjà vu. Statistiques et Mes listes ne recalculent plus tout à chaque affichage."),
                Fonctionnalite(symbole: "moon.stars", titre: "« Hier soir : regardé ? »",
                               detail: "Une soirée passée ne s'efface plus en silence : Ce soir demande si tu as regardé le film — « Regardé », « Ce soir » ou l'oublier. L'accueil le rappelle."),
                Fonctionnalite(symbole: "bell", titre: "Une cloche sur chaque passage télé",
                               detail: "Dans le programme télé et sur l'accueil : « me le rappeler un quart d'heure avant », pour n'importe quel film ou série, même hors de ta liste."),
                Fonctionnalite(symbole: "sparkles.tv", titre: "Regardable ce soir, dans ta liste",
                               detail: "Sur l'accueil : ce que tu voulais voir et qui est sous la main, sur ton NAS, tes plateformes ou à la télé ce soir."),
                Fonctionnalite(symbole: "textformat.size", titre: "Texte agrandi et contraste",
                               detail: "Les heures, les dates et les titres suivent la taille de texte choisie dans iOS. En apparence claire, l'orange des textes est plus soutenu, pour rester lisible."),
            ]
        ),
        NoteVersion(
            numero: "2.9",
            date: "18 septembre 2026",
            resume: "Un Profil en images, des Réglages en tableau de bord, et l'apparence claire ou sombre au choix.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.crop.circle", titre: "Profil en images",
                               detail: "Tes dernières notes en affiches, tes acteurs en portraits (une cloche sur ceux que tu suis), tes goûts en puces. Les chiffres ne s'imposent plus : « Tes statistiques », en bas de page, ouvre la page qui les réunit tous, avec ta collection et ton année en cartes."),
                Fonctionnalite(symbole: "gearshape", titre: "Réglages en tableau de bord",
                               detail: "En tête, « État de Séance » : ce qui est en ordre en vert, ce qui manque en orange, et un toucher mène au réglage. Dessous, une carte par réglage avec son état courant ; deux colonnes sur le Mac et l'iPad. L'accueil se personnalise aussi d'ici."),
                Fonctionnalite(symbole: "circle.lefthalf.filled", titre: "Apparence sombre, claire ou automatique",
                               detail: "Réglages › Apparence. Sombre reste l'apparence d'origine ; « Automatique » suit ton appareil. Les grandes images gardent leur texte clair dans les deux cas."),
                Fonctionnalite(symbole: "play.circle", titre: "Lecture du NAS, épisode par épisode",
                               detail: "Pour une série, chaque épisode présent sur le NAS porte son ▶︎ dans la liste « Épisodes » — la seule liste de la fiche — et « À regarder » aussi ; les saisons du NAS sont marquées, et « Sur ton NAS » résume ce qu'il contient, saison par saison. Pour un film, toute la ligne lance la lecture. Le choix entre Infuse et VLC a sa page, Réglages › Lecture, qui dit si chaque app est installée et ce qu'elle demande."),
                Fonctionnalite(symbole: "arrow.uturn.backward", titre: "Retour depuis Mes listes",
                               detail: "Une fiche ouverte depuis la grille d'affiches ou depuis « À venir » pouvait s'empiler plusieurs fois : le retour ne ramenait plus à Mes listes. Corrigé, et vérifié par un test."),
                Fonctionnalite(symbole: "arrow.counterclockwise", titre: "Remettre les statistiques à zéro",
                               detail: "En bas des statistiques. Rien n'est effacé : tes titres restent vus et notés, tes goûts ne changent pas ; seuls les compteurs repartent. Annulable juste après."),
                Fonctionnalite(symbole: "trash", titre: "Effacer le journal",
                               detail: "Réglages › À propos › Journal : « Partager » et « Effacer » ont chacun leur ligne — sur une même ligne, ils se déclenchaient ensemble."),
            ]
        ),
        NoteVersion(
            numero: "2.8",
            date: "18 septembre 2026",
            resume: "Tes appareils se tiennent à jour par un dossier d'iCloud Drive, et une sauvegarde s'envoie par AirDrop.",
            fonctionnalites: [
                Fonctionnalite(symbole: "icloud", titre: "Synchronisation par iCloud Drive",
                               detail: "Réglages › Sauvegarde : choisis le même dossier d'iCloud Drive sur ton iPhone, ton iPad et ton Mac. Chaque appareil y dépose son fichier et reprend ceux des autres à chaque ouverture de Séance. Sans compte à créer ; elle ajoute et complète, sans rien supprimer."),
                Fonctionnalite(symbole: "square.and.arrow.up.on.square", titre: "Envoyer à un autre appareil",
                               detail: "AirDrop, Messages ou Mail : l'autre appareil — même sur un autre compte Apple — reçoit un fichier « .seance », propose « Ouvrir avec Séance », et l'import se confirme d'un geste."),
                Fonctionnalite(symbole: "doc", titre: "Des sauvegardes qui s'ouvrent dans Séance",
                               detail: "Toucher un fichier « .seance » dans Fichiers ouvre Séance et propose de l'importer."),
            ]
        ),
        NoteVersion(
            numero: "2.7",
            date: "18 septembre 2026",
            resume: "Une sauvegarde enfin complète pour passer d'un appareil à l'autre, et Siri qui comprend mieux.",
            fonctionnalites: [
                Fonctionnalite(symbole: "externaldrive.badge.checkmark", titre: "Sauvegarde complète",
                               detail: "Le fichier emporte maintenant tes soirées prévues, tes idées reportées, les acteurs de tes titres, les logos de tes plateformes, ce que Séance sait déjà de tes acteurs suivis, et tes réglages : prénom, accueil, tri, alertes, adresse du NAS. Jamais une clé ni un mot de passe."),
                Fonctionnalite(symbole: "arrow.triangle.merge", titre: "Un import qui complète",
                               detail: "Un titre déjà présent n'était jamais mis à jour. Désormais, un film vu ou noté sur l'autre appareil le devient ici ; rien n'est effacé, et rien ne recule."),
                Fonctionnalite(symbole: "list.bullet.clipboard", titre: "Un compte rendu honnête",
                               detail: "Après l'import, Séance dit tout ce qui est arrivé — titres, soirées, listes, acteurs, goûts, réglages — et te rappelle de saisir la clé TMDB si elle manque."),
                Fonctionnalite(symbole: "mic", titre: "Siri",
                               detail: "« Séance » étant un mot courant, tu peux aussi dire « Séance Ciné ». Plus de tournures (« Ce soir avec Séance », « Mets … dans ma soirée »), et tes nouveaux titres sont connus de Siri dès que tu quittes l'app."),
            ]
        ),
        NoteVersion(
            numero: "2.6",
            date: "18 septembre 2026",
            resume: "« À venir » en rangée de jours, Mes listes en affiches, un NAS plus parlant, et l'app entièrement testée sur l'iPhone et l'iPad mini.",
            fonctionnalites: [
                Fonctionnalite(symbole: "calendar", titre: "« À venir » comme le programme télé",
                               detail: "Une rangée de jours — « Tout » d'abord, puis chaque jour où il se passe quelque chose — et chaque rendez-vous en grande carte : sa date en grand, épisode, saison, sortie ou télé, et « Aujourd'hui » mis en avant."),
                Fonctionnalite(symbole: "square.grid.2x2", titre: "Mes listes en affiches",
                               detail: "Grille ou liste, comme dans Explorer. Sur chaque affiche : où regarder, la cloche si le titre est surveillé, et dessous son prochain rendez-vous, ta note ou tes épisodes vus. Clic droit ou appui long : les mêmes actions qu'en liste."),
                Fonctionnalite(symbole: "externaldrive", titre: "Le NAS dans le même style",
                               detail: "« Nouveaux sur ton NAS » en grandes cartes, le dossier NEW tout en images, et sur les affiches un liseré orange pour ce qui est dans ta liste, un œil pour ce que tu as vu, et la note TMDB."),
                Fonctionnalite(symbole: "magnifyingglass", titre: "Sources NAS et Télé réparées",
                               detail: "Avec « Français ou anglais » (le réglage d'origine d'Explorer), les sources NAS et Télé ne trouvaient rien. Elles listent maintenant tous leurs titres. Les quatre sources tiennent sur l'écran de l'iPhone."),
                Fonctionnalite(symbole: "bolt", titre: "Profil plus léger",
                               detail: "Tes acteurs favoris ne sont plus recalculés à chaque affichage, seulement quand tes visionnages changent."),
                Fonctionnalite(symbole: "checkmark.seal", titre: "Testée sans clé TMDB",
                               detail: "En développement, un faux TMDB rejoue des réponses enregistrées : l'Accueil, Ce soir, Explorer, Mes listes, le NAS et le Profil sont parcourus et capturés automatiquement sur l'iPhone, et l'app a été vue sur l'iPad mini."),
            ]
        ),
        NoteVersion(
            numero: "2.5",
            date: "18 septembre 2026",
            resume: "Réglages ne fige plus l'iPhone ; programme télé et Ce soir refaits en grandes cartes ; source des idées, accueil à ta mesure et ton prénom.",
            fonctionnalites: [
                Fonctionnalite(symbole: "gearshape", titre: "Réglages sur l'iPhone",
                               detail: "Ouvrir Réglages depuis l'engrenage du Profil figeait l'app, puis iOS la fermait. La page et toutes ses sous-pages s'ouvrent de nouveau, et un test automatique les parcourt."),
                Fonctionnalite(symbole: "tv", titre: "Programme télé par soirée",
                               detail: "Un jour à la fois, choisi dans une rangée de dates. « En ce moment » et « En soirée » en grandes cartes ; le reste de la journée en lignes, l'heure devant."),
                Fonctionnalite(symbole: "clock", titre: "L'heure en grand",
                               detail: "Sur chaque carte : la chaîne, l'heure de début et de fin, « Dans 35 min », et en direct l'avancement avec le temps qui reste."),
                Fonctionnalite(symbole: "rectangle.stack", titre: "Épisodes réunis",
                               detail: "Les épisodes d'une série qui s'enchaînent sur une chaîne ne font plus qu'une carte : « S08E01 et E02 »."),
                Fonctionnalite(symbole: "bookmark", titre: "Tes titres à la télé",
                               detail: "Un film de ta liste qui passe à la télé porte un liseré orange et « Dans ta liste » ; un titre déjà vu est signalé aussi."),
                Fonctionnalite(symbole: "calendar", titre: "Prévoir depuis le programme",
                               detail: "Clic droit ou appui long sur un passage : « Prévoir pour ce soir-là » l'ajoute à la soirée du jour de diffusion."),
                Fonctionnalite(symbole: "moon.stars", titre: "Ce soir, dans le même esprit",
                               detail: "La même rangée de jours que le programme télé : ce soir et la semaine, plus les soirées lointaines déjà prévues. Chaque titre en grande carte, avec son image, où le regarder, « Regardé » bien visible, ou « Ce soir » pour le ramener."),
                Fonctionnalite(symbole: "square.grid.2x2", titre: "Source des idées dans Explorer",
                               detail: "Toutes, Streaming, NAS ou Télé (ce soir, cette semaine) : un choix en haut d'Explorer, qui part de la bonne liste."),
                Fonctionnalite(symbole: "slider.horizontal.3", titre: "Accueil à ta mesure",
                               detail: "« Seulement sur mes plateformes » remplace la liste qui doublait Réglages › Plateformes. Tu choisis le nombre de titres du bandeau (3, 5, 8), du Top (3, 5, 10) et de « Du moment » (10, 20, 30), et si la télé montre aussi les séries."),
                Fonctionnalite(symbole: "person", titre: "Ton prénom",
                               detail: "Réglages › Toi : Séance te salue sur l'accueil et te propose « Des idées pour toi ». Au même endroit, le nombre d'idées du soir : 3, 5 ou 10."),
            ]
        ),
        NoteVersion(
            numero: "2.4",
            date: "18 septembre 2026",
            resume: "Prévoir et ranger depuis partout, listes nommées, où regarder sur les affiches, et des données versionnées.",
            fonctionnalites: [
                Fonctionnalite(symbole: "calendar", titre: "Prévoir depuis partout",
                               detail: "« Prévoir pour une soirée… » dans le menu Plus de la fiche, au clic droit ou à l'appui long sur une affiche, et dans Mes listes."),
                Fonctionnalite(symbole: "list.bullet.rectangle.portrait", titre: "Listes nommées",
                               detail: "L'onglet Listes de Mes listes : crée « Soirées Statham », range-y des titres par « Ajouter à une liste… », renomme, supprime. Et une recherche dans tes propres titres."),
                Fonctionnalite(symbole: "play.tv", titre: "Où regarder, sur l'affiche",
                               detail: "Un petit badge en coin : le logo de ta plateforme, le NAS, ou la télé de ce soir."),
                Fonctionnalite(symbole: "star", titre: "Noter après avoir regardé",
                               detail: "Dans Ce soir, ✓ sur un film propose aussitôt sa note de 1 à 10."),
                Fonctionnalite(symbole: "house", titre: "Ta soirée sur l'accueil",
                               detail: "Sous le bandeau, ce qui est prévu ce soir ou pour ta prochaine soirée."),
                Fonctionnalite(symbole: "checkmark.bubble", titre: "Confirmations partout",
                               detail: "À voir, Vu et Retirer confirment depuis la fiche, avec Annuler ; le message se centre sur le contenu, et les personnes sans photo ont une silhouette."),
                Fonctionnalite(symbole: "externaldrive.badge.checkmark", titre: "Données versionnées",
                               detail: "Chaque évolution du modèle de données a désormais sa version et sa migration testée ; tes données actuelles s'ouvrent sans changement."),
            ]
        ),
        NoteVersion(
            numero: "2.3",
            date: "18 septembre 2026",
            resume: "Prévoir un film ou une série pour la soirée de ton choix.",
            fonctionnalites: [
                Fonctionnalite(symbole: "calendar", titre: "Soirées à la date de ton choix",
                               detail: "Dans Ce soir, le calendrier d'un titre le prévoit pour un autre soir ; « Ajouter » remplit la soirée de la date choisie. Les prochaines soirées s'affichent sous celle de ce soir."),
                Fonctionnalite(symbole: "bell", titre: "Rappel le jour venu",
                               detail: "À l'heure des alertes, Séance rappelle ce que tu as prévu pour la soirée, et le titre passe tout seul dans « Ce soir »."),
                Fonctionnalite(symbole: "iphone", titre: "Fiche sur iPhone",
                               detail: "Les fiches avec bande-annonce ne débordent plus de l'écran."),
            ]
        ),
        NoteVersion(
            numero: "2.2",
            date: "18 septembre 2026",
            resume: "Ce soir, en plus simple : seulement ce que tu as choisi de regarder.",
            fonctionnalites: [
                Fonctionnalite(symbole: "moon.stars.fill", titre: "Ce soir, ta sélection",
                               detail: "La page ne montre que les films et séries gardés pour ce soir, avec où les regarder ; ✓ quand c'est regardé, ✕ pour retirer."),
                Fonctionnalite(symbole: "plus.circle", titre: "Ajouter",
                               detail: "Rendez-vous du jour, épisodes à regarder, ta liste regardable ce soir et idées selon tes goûts sont réunis dans une feuille, à un geste de la page."),
                Fonctionnalite(symbole: "hand.tap", titre: "Profil",
                               detail: "« Mes goûts » répond sur toute la ligne, et la fiche d'un acteur suivi s'ouvre devant la liste au lieu de se ranger dessous."),
            ]
        ),
        NoteVersion(
            numero: "2.1",
            date: "17 septembre 2026",
            resume: "Le parcours d'un utilisateur, corrigé point par point : idées qui se renouvellent, fiches de séries justes, écrans plus nets.",
            fonctionnalites: [
                Fonctionnalite(symbole: "sparkles", titre: "Idées qui se renouvellent",
                               detail: "Cinq idées restent affichées, chaque idée traitée laisse sa place à la suivante ; « Annuler » la remet. Chacune dit où la regarder, et une envie « pas trop longue » est comprise."),
                Fonctionnalite(symbole: "tv", titre: "Séries : où en est la diffusion",
                               detail: "Épisode du jour, prochain épisode, chaîne qui la diffuse : plus de « introuvable » pour une série en cours, et « Me prévenir » des épisodes."),
                Fonctionnalite(symbole: "magnifyingglass", titre: "Explorer plus net",
                               detail: "Portées Tout / Films / Séries / Acteurs seulement pendant la recherche, en-tête « Titres », personnes avec photo d'abord."),
                Fonctionnalite(symbole: "list.bullet", titre: "Mes listes",
                               detail: "Tris directement dans le menu, « Tout supprimer » rangé sous « … », filtre « Regardable ce soir » remis à zéro en quittant et titres masqués comptés, « Remettre à voir » pour une série en cours."),
                Fonctionnalite(symbole: "person.2", titre: "Acteurs favoris honnêtes",
                               detail: "Un acteur vu dans un seul titre n'est pas un favori : le classement attend d'avoir de quoi classer."),
                Fonctionnalite(symbole: "macwindow", titre: "Mac",
                               detail: "Titre de fenêtre rétabli après une feuille, barre de retour visible quand la fiche défile."),
            ]
        ),
        NoteVersion(
            numero: "2.0",
            date: "17 septembre 2026",
            resume: "Des idées pour ce soir selon tes goûts, une app plus claire et qui prévient quand quelque chose cloche.",
            fonctionnalites: [
                Fonctionnalite(symbole: "sparkles", titre: "Idées pour ce soir",
                               detail: "Dans Ce soir, cinq titres regardables sur tes plateformes, choisis selon tes goûts et tes notes ; « Je regarde », « Pas ce soir » ou « Jamais ». Précise ton envie, avec Claude en option."),
                Fonctionnalite(symbole: "bell.slash", titre: "Notifications coupées ? C'est dit",
                               detail: "Sur une fiche avec cloche, dans À venir et pour les acteurs suivis, avec de quoi les rallumer."),
                Fonctionnalite(symbole: "film", titre: "Où regarder, même au cinéma",
                               detail: "Au cinéma depuis le…, bientôt en salle, date de streaming : plus de « introuvable » pour un film récent, et « Me prévenir de sa sortie »."),
                Fonctionnalite(symbole: "arrow.uturn.backward", titre: "Annuler",
                               detail: "Pas intéressé, retirer, terminé, supprimer des terminés : le message propose d'annuler pendant cinq secondes."),
                Fonctionnalite(symbole: "textformat", titre: "Boutons nommés",
                               detail: "Chaque action d'une fiche porte son nom : À voir, Vu, Alertes, Bande-annonce, Plus."),
                Fonctionnalite(symbole: "square.stack", titre: "Ce soir sans doublon",
                               detail: "Un titre n'apparaît qu'une fois, et « regardable ce soir » suit la même règle que Mes listes."),
                Fonctionnalite(symbole: "magnifyingglass", titre: "Explorer utile d'emblée",
                               detail: "En français ou en anglais, sur tes plateformes, en puces à retirer ; un seul bouton Filtres."),
                Fonctionnalite(symbole: "slider.horizontal.3", titre: "Accueil personnalisable",
                               detail: "Plateformes et sections (Top 10, télé, Du moment, NAS) à afficher, et un rappel quand l'accueil est limité."),
                Fonctionnalite(symbole: "person.crop.circle", titre: "Profil plus parlant",
                               detail: "Ta collection en chiffres, tes dernières notes et tes acteurs favoris."),
                Fonctionnalite(symbole: "keyboard", titre: "Clavier et Mac",
                               detail: "⌘1 à ⌘6 pour les onglets, ⌘F pour chercher ; fiche sur une colonne dans une fenêtre étroite, « Lire la suite »."),
                Fonctionnalite(symbole: "clock.badge.exclamationmark", titre: "Rappel d'expiration",
                               detail: "À propos indique jusqu'à quand l'installation est valable, et une notification prévient la veille."),
            ]
        ),
        NoteVersion(
            numero: "1.5",
            date: "17 septembre 2026",
            resume: "« Du moment » sur l'accueil, et les terminés se suppriment de Mes listes.",
            fonctionnalites: [
                Fonctionnalite(symbole: "flame.fill", titre: "Du moment",
                               detail: "Une seule section à la place des tendances et des nouveautés : sorties et nouveaux épisodes du mois, les plus populaires d'abord."),
                Fonctionnalite(symbole: "trash", titre: "Supprimer des terminés",
                               detail: "Un titre ou tous d'un coup : ils quittent la liste, mais restent vus, notés et comptés, et ne te sont pas reproposés."),
            ]
        ),
        NoteVersion(
            numero: "1.4",
            date: "17 septembre 2026",
            resume: "Top 10 de l'année, Regardable ce soir dans Mes listes, actions rapides sur les affiches, menu masquable sur le Mac.",
            fonctionnalites: [
                Fonctionnalite(symbole: "trophy.fill", titre: "Top 10 de l'année",
                               detail: "Sur l'accueil, les cinq films et les cinq séries les mieux notés depuis un an, à la place de « Pour toi » et « Parce que tu as aimé »."),
                Fonctionnalite(symbole: "sidebar.left", titre: "Menu masquable sur le Mac",
                               detail: "Le bouton en haut à gauche, ou ⌃⌘S, cache le menu pour laisser toute la place à la page."),
                Fonctionnalite(symbole: "chevron.left.forwardslash.chevron.right", titre: "Flèches des carrousels",
                               detail: "Sur le Mac, elles sont rangées à droite de chaque rangée et sous le bandeau : un clic fait défiler au lieu d'ouvrir une fiche."),
                Fonctionnalite(symbole: "speaker.slash.fill", titre: "Bandes-annonces",
                               detail: "Fermer le lecteur, ou quitter la fenêtre, arrête la vidéo et le son."),
                Fonctionnalite(symbole: "moon.stars", titre: "Regardable ce soir",
                               detail: "Dans Mes listes, ne garder que ce qui est sur le NAS, dans tes abonnements ou à la télé ce soir ; trier par durée ou par titre."),
                Fonctionnalite(symbole: "hand.tap", titre: "Actions rapides",
                               detail: "Appui long sur une affiche, clic droit sur le Mac : À voir, Vu, Déjà vu avant, Ma soirée, Pas intéressé."),
                Fonctionnalite(symbole: "character.book.closed", titre: "Genres en français",
                               detail: "Les noms des genres sont livrés avec l'app : plus de « Genre 28 » sans réseau."),
            ]
        ),
        NoteVersion(
            numero: "1.3",
            date: "17 septembre 2026",
            resume: "Acteurs : recherche, suivi, statistiques justes ; titres similaires et note dans l'en-tête.",
            fonctionnalites: [
                Fonctionnalite(symbole: "magnifyingglass", titre: "Recherche par acteur",
                               detail: "Dans Explorer, la portée « Acteurs », et « Avec Jason Statham » dès qu'un nom est tapé : ses titres les plus connus et un bouton Filtrer."),
                Fonctionnalite(symbole: "bell.badge", titre: "Suivre un acteur",
                               detail: "La cloche de sa fiche : Séance te prévient quand un nouveau film avec lui est annoncé. La liste est dans Profil."),
                Fonctionnalite(symbole: "person.2.fill", titre: "Acteurs dans les statistiques",
                               detail: "Les dix acteurs les plus regardés ; sa fiche montre en tête exactement les titres comptés."),
                Fonctionnalite(symbole: "sparkles", titre: "Parce que tu as aimé…",
                               detail: "Sur l'accueil, les titres que TMDB rapproche de ceux que tu as notés 8 ou plus."),
                Fonctionnalite(symbole: "star.fill", titre: "Ta note dans l'en-tête",
                               detail: "À côté de la note TMDB, sur chaque fiche notée."),
                Fonctionnalite(symbole: "eye.slash", titre: "Marquer comme non vu",
                               detail: "Un « Vu » ou « Déjà vu avant » touché par erreur s'annule depuis l'œil de la fiche."),
            ]
        ),
        NoteVersion(
            numero: "1.2",
            date: "17 septembre 2026",
            resume: "Statistiques et bilan de l'année, widgets, Siri, fiche acteur, premier lancement guidé et vraie mise en page Mac.",
            fonctionnalites: [
                Fonctionnalite(symbole: "chart.bar.fill", titre: "Statistiques",
                               detail: "Heures regardées, mois par mois, acteurs et genres favoris, plus grosse soirée ; le bilan de l'année en cartes à partager."),
                Fonctionnalite(symbole: "square.grid.2x2.fill", titre: "Widgets",
                               detail: "Ma soirée, prochains épisodes à cocher d'un ✓ et À venir, sur l'écran d'accueil et l'écran verrouillé."),
                Fonctionnalite(symbole: "mic.fill", titre: "Siri et Raccourcis",
                               detail: "« Qu'est-ce que je regarde ce soir avec Séance ? » et « Ajoute Reacher à ma soirée dans Séance »."),
                Fonctionnalite(symbole: "person.crop.rectangle.stack", titre: "Fiche acteur",
                               detail: "Sa filmographie avec ce que tu as vu, ce qui reste et ce qui est regardable ce soir."),
                Fonctionnalite(symbole: "hand.wave.fill", titre: "Premier lancement",
                               detail: "Plateformes, genres préférés et une dizaine de films à noter : les suggestions sont justes dès le départ."),
                Fonctionnalite(symbole: "checkmark.circle", titre: "Après le NAS",
                               detail: "De retour d'Infuse ou de VLC, Séance propose de marquer le film ou l'épisode comme vu."),
                Fonctionnalite(symbole: "moon.stars", titre: "Ce soir allégé",
                               detail: "La page se concentre sur ta soirée, tes épisodes et ta liste ; la recherche d'un titre se fait dans Explorer."),
                Fonctionnalite(symbole: "play.circle.fill", titre: "Lecture directe dans Infuse",
                               detail: "Le film ou l'épisode s'ouvre dans la bibliothèque d'Infuse et démarre aussitôt ; VLC lit toujours le fichier du NAS."),
                Fonctionnalite(symbole: "photo.stack", titre: "Affiches fiables",
                               detail: "Les images interrompues se rechargent et restent en cache : plus d'affiches grises."),
                Fonctionnalite(symbole: "internaldrive", titre: "Espace utilisé",
                               detail: "Dans À propos : la place de l'app, de tes données et des caches, avec les affiches à vider. Les copies en double du NAS sont nommées dans Réglages › NAS."),
                Fonctionnalite(symbole: "macwindow", titre: "Mise en page Mac",
                               detail: "Barre latérale, fiche en deux colonnes avec où regarder à droite, grandes affiches dans Explorer."),
                Fonctionnalite(symbole: "person.crop.circle", titre: "Profil et Réglages",
                               detail: "Tes goûts, tes statistiques et ton bilan dans Profil ; la configuration de l'app dans Réglages, ouverts par l'engrenage sur l'iPhone et par ⌘, sur le Mac."),
                Fonctionnalite(symbole: "clock.arrow.circlepath", titre: "Déjà vu avant",
                               detail: "Un film, une saison ou toute une série vus il y a longtemps : ils sortent des suggestions sans fausser tes statistiques."),
                Fonctionnalite(symbole: "star.fill", titre: "Ta note",
                               detail: "De 1 à 10 sur la fiche d'un film ou d'une série vus : Séance en déduit tes genres et tes acteurs préférés, et te propose des titres du même type."),
            ]
        ),
        NoteVersion(
            numero: "1.1",
            date: "17 septembre 2026",
            resume: "Suivi des séries, alertes complètes et version Mac.",
            fonctionnalites: [
                Fonctionnalite(symbole: "checklist", titre: "Épisodes",
                               detail: "Cases à cocher par saison, « vu jusqu'ici », notes, prochain épisode à regarder et progression."),
                Fonctionnalite(symbole: "bell.badge.fill", titre: "Alertes",
                               detail: "Cloche sur chaque fiche : annonce d'une saison ou d'une sortie, la veille, le jour même, arrivée sur tes plateformes ou en location, passages à la télé."),
                Fonctionnalite(symbole: "calendar", titre: "À venir",
                               detail: "Le calendrier des prochains épisodes, sorties et passages télé de tes titres surveillés."),
                Fonctionnalite(symbole: "play.tv", titre: "Accueil par plateforme",
                               detail: "Choisir Netflix ou Prime Video filtre les nouveautés, les titres populaires et les suggestions ; « Tout voir » ouvre chaque liste complète."),
                Fonctionnalite(symbole: "list.bullet.rectangle", titre: "Mes listes",
                               detail: "Glisser pour marquer terminé, retirer ou couper les alertes ; progression et prochaine date sur chaque titre."),
                Fonctionnalite(symbole: "desktopcomputer", titre: "Version Mac",
                               detail: "La même app sur le Mac, avec lecture directe des films du NAS monté."),
                Fonctionnalite(symbole: "stethoscope", titre: "Journal",
                               detail: "Les problèmes rencontrés, expliqués simplement avec ce que tu peux faire, dans À propos."),
            ]
        ),
        NoteVersion(
            numero: "1.0",
            date: "16 septembre 2026",
            resume: "Première version stable : NAS, Explorer et fiches fiabilisés à l'usage sur l'iPhone.",
            fonctionnalites: [
                Fonctionnalite(symbole: "externaldrive.fill", titre: "NAS fiable",
                               detail: "Dossiers retrouvés quelle que soit l'écriture des accents, accès au réseau local demandé proprement, bibliothèque relue dès que les réglages changent."),
                Fonctionnalite(symbole: "line.3.horizontal.decrease", titre: "Explorer vérifié",
                               detail: "Chaque filtre réduit bien les résultats ; NAS, télé et titres vus partent de ta liste."),
                Fonctionnalite(symbole: "calendar", titre: "Nouveautés datées",
                               detail: "Date de sortie des films et des nouveaux épisodes du jour ou de la semaine."),
                Fonctionnalite(symbole: "circle.grid.2x1.fill", titre: "Actions en icônes",
                               detail: "À voir, vu, bande-annonce, lecture : des boutons compacts partout."),
                Fonctionnalite(symbole: "info.circle", titre: "Versions",
                               detail: "L'historique des versions et de leurs fonctionnalités, ici même."),
            ]
        ),
        NoteVersion(
            numero: "0.9",
            date: "16 septembre 2026",
            resume: "Première version complète à l'essai sur l'iPhone de Patrick.",
            fonctionnalites: [
                Fonctionnalite(symbole: "house.fill", titre: "Accueil",
                               detail: "Tendances, nouveautés du jour et de la semaine, action sur tes plateformes, idées « Pour toi », télé du soir et aperçu du NAS."),
                Fonctionnalite(symbole: "sparkles", titre: "Ce soir",
                               detail: "Des suggestions selon ton envie et tes goûts, toutes vérifiées dans TMDB, avec Claude en option."),
                Fonctionnalite(symbole: "magnifyingglass", titre: "Explorer",
                               detail: "Recherche de films, séries et personnes, filtres détaillés et filtres enregistrés."),
                Fonctionnalite(symbole: "film", titre: "Fiches",
                               detail: "Où regarder en Suisse, bandes-annonces en streaming, casting et lecture depuis le NAS."),
                Fonctionnalite(symbole: "bookmark.fill", titre: "Mes listes",
                               detail: "Titres à voir, en cours et terminés."),
                Fonctionnalite(symbole: "tv.fill", titre: "Télévision",
                               detail: "Programmes de la RTS et des chaînes françaises, reconnus dans TMDB."),
                Fonctionnalite(symbole: "externaldrive.fill", titre: "NAS",
                               detail: "Bibliothèque du Synology lue en SMB, films reconnus, lecture dans Infuse ou VLC."),
                Fonctionnalite(symbole: "gearshape.fill", titre: "Réglages",
                               detail: "Classés par thème ; données sur l'iPhone, clés et mots de passe dans le trousseau."),
            ]
        ),
    ]
}

/// Onglet « Versions » d'À propos : une ligne repliable par version, toutes fermées au départ
/// pour garder la page courte.
struct ListeVersions: View {
    let versionInstallee: String

    @State private var ouvertes: Set<String> = []

    var body: some View {
        Section {
            ForEach(NoteVersion.historique) { version in
                DisclosureGroup(isExpanded: Binding(
                    get: { ouvertes.contains(version.numero) },
                    set: { ouverte in
                        if ouverte { ouvertes.insert(version.numero) } else { ouvertes.remove(version.numero) }
                    }
                )) {
                    ForEach(version.fonctionnalites) { fonctionnalite in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: fonctionnalite.symbole)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28, height: 28)
                                .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fonctionnalite.titre).font(.subheadline.weight(.semibold))
                                Text(fonctionnalite.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    entete(version)
                }
                .tint(Theme.accent)
            }
        } footer: {
            Text("Touche une version pour voir ce qu'elle apporte.")
        }
    }

    private func entete(_ version: NoteVersion) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Version \(version.numero)").font(.headline)
                if version.numero == versionInstallee {
                    Text("installée")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.black)
                }
                Spacer()
                Text(version.date).font(.caption).foregroundStyle(.secondary)
            }
            Text(version.resume)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

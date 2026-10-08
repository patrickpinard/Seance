import Foundation

/// Une version de Séance et ce qu'elle apporte, vu de haut. La plus récente en premier ;
/// son numéro doit correspondre à `MARKETING_VERSION` dans `project.yml`.
///
/// Ces notes sont les mêmes partout (6.3) : l'app les montre dans À propos › Versions (`ListeVersions`),
/// l'Apple TV dans Réglages › Versions (`PageVersionsTV`) — d'où ce fichier sans vue, partagé par `project.yml`.
/// Le jour et l'heure où chaque version est arrivée sur cet appareil (8.1) : l'app note sa version au lancement, avec
/// la date de son paquet (posée par l'installation). Commun à l'iPhone, à l'iPad, au Mac et à l'Apple TV.
enum InstallationsVersions {
    /// Nouvelle clé en 8.2.1 : les heures notées par la 8.1 et la 8.2 étaient fausses, elles sont oubliées.
    private static let cle = "versions.installations.3"

    /// À appeler au lancement : retient le jour et l'heure d'installation de la version en cours.
    static func noter() {
        guard let numero = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let date = dateInstallation else { return }
        var connues = lues()
        guard connues[numero] != date else { return }
        connues[numero] = date
        UserDefaults.standard.set(connues.mapValues(\.timeIntervalSince1970), forKey: cle)
    }

    /// L'heure d'installation : celle de la compilation, inscrite dans l'Info.plist par `project.yml` — `installer.sh`
    /// compile juste avant d'installer. (Les dates des dossiers et des fichiers installés sont remises à zéro par iOS :
    /// la 8.2 affichait « 1er janvier 1970 ».)
    private static var dateInstallation: Date? {
        (Bundle.main.object(forInfoDictionaryKey: "SeanceCompileeLe") as? String).flatMap { try? Date($0, strategy: .iso8601) }
    }

    static func lues() -> [String: Date] {
        ((UserDefaults.standard.dictionary(forKey: cle) as? [String: Double]) ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// « Installée le 26 septembre 2026 à 14:32 », si cette version l'a été sur cet appareil.
    static func libelle(_ numero: String) -> String? {
        lues()[numero].map { "Installée le \($0.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_CH")))) à \($0.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH"))))" }
    }
}

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
            numero: "8.12",
            date: "8 octobre 2026",
            resume: "Plus sûre et plus solide : l'app se réinstalle seule, les plantages se voient, les vignettes des souvenirs viennent du Mac.",
            fonctionnalites: [
                Fonctionnalite(symbole: "arrow.clockwise", titre: "Réinstallée automatiquement",
                               detail: "Le Mac mini réinstalle Séance sur l'iPhone, l'iPad, les Apple TV et le Mac avant les 7 jours du compte gratuit, dès qu'ils sont joignables."),
                Fonctionnalite(symbole: "bolt.trianglebadge.exclamationmark", titre: "Les arrêts visibles",
                               detail: "Réglages › À propos liste les arrêts brusques de Séance sur l'iPhone et l'iPad, avec la page ouverte, comme sur l'Apple TV."),
                Fonctionnalite(symbole: "photo.on.rectangle", titre: "Vignettes des souvenirs",
                               detail: "Le Mac les fabrique et les dépose sur le NAS ; l'iPhone, l'iPad et la TV les y lisent au lieu de relire chaque vidéo, et les gardent pour de bon."),
                Fonctionnalite(symbole: "lock.shield", titre: "Plus sûre",
                               detail: "Le mot de passe du NAS n'est plus transmis aux apps VLC et Infuse ; la lecture envoyée à l'Apple TV refuse une demande rejouée."),
            ]
        ),
        NoteVersion(
            numero: "8.11",
            date: "6 octobre 2026",
            resume: "Mes listes réduites à l'essentiel : à voir, en cours, à venir. Ce que tu as regardé passe dans les statistiques.",
            fonctionnalites: [
                Fonctionnalite(symbole: "list.bullet", titre: "Trois listes",
                               detail: "Mes listes ne garde que « À voir », « En cours » et « À venir », sur tous les appareils. Les favoris deviennent des « J'aime » ; les listes nommées disparaissent des menus."),
                Fonctionnalite(symbole: "checkmark.circle", titre: "Ce que tu as regardé",
                               detail: "Tes titres terminés, mois par mois, se retrouvent dans Préférences › Statistiques, sur l'iPhone, l'iPad, le Mac et l'Apple TV."),
                Fonctionnalite(symbole: "arrow.uturn.backward.circle", titre: "Une nouvelle saison ? La série revient",
                               detail: "Une série terminée qui annonce une nouvelle saison repart « En cours », et retrouve les Nouveautés, les widgets et Siri. Vérifié chaque jour, cloche ou non."),
                Fonctionnalite(symbole: "externaldrive", titre: "Un partage entier",
                               detail: "Sans dossier indiqué dans les réglages du NAS, tout le partage est lu : pratique pour les films posés à la racine d'un Mac."),
                Fonctionnalite(symbole: "macbook", titre: "Le Mac ne plante plus au premier lancement",
                               detail: "L'écran de bienvenue s'ouvre normalement."),
            ]
        ),
        NoteVersion(
            numero: "8.10",
            date: "2 octobre 2026",
            resume: "L'Apple TV plus claire et plus rapide : un curseur qu'on voit, une recherche qui trouve tout, et « Reprendre » pour chacun.",
            fonctionnalites: [
                Fonctionnalite(symbole: "hand.point.up.left", titre: "Un curseur qu'on voit",
                               detail: "Sur l'Apple TV, seul le curseur est blanc plein ; ce qui est choisi garde un contour blanc. Le focus arrive au bon endroit : sur « Auj. », sur le bouton principal de la fiche, sur les commandes de Mes listes."),
                Fonctionnalite(symbole: "magnifyingglass", titre: "La recherche trouve tout",
                               detail: "Films, séries et personnes ensemble, ce qui est sur le NAS en tête, quelle que soit la catégorie choisie."),
                Fonctionnalite(symbole: "person.2", titre: "« Reprendre » pour chacun",
                               detail: "Les films entamés sont propres à chaque personne de la famille, sur tous les appareils."),
                Fonctionnalite(symbole: "gauge.with.dots.needle.67percent", titre: "Plus rapide",
                               detail: "Images à la bonne taille et gardées sur la TV, bibliothèque du NAS mise à jour au lieu d'être refaite, lecture qui démarre à la bonne position."),
                Fonctionnalite(symbole: "playpause", titre: "Dans le Centre de contrôle",
                               detail: "Le titre, l'affiche et la position s'affichent sur l'iPhone et dans sa télécommande pour l'Apple TV ; lecture, pause et sauts de 10 secondes y répondent."),
                Fonctionnalite(symbole: "checkmark.circle", titre: "Plus d'épisode coché par erreur",
                               detail: "Un épisode absent du NAS demande : le regarder ailleurs, ou le marquer vu. « NEW » devient « Nouveaux »."),
            ]
        ),
        NoteVersion(
            numero: "8.9",
            date: "1er octobre 2026",
            resume: "Qui est-ce ? Sur l'Apple TV, une pause montre les visages du film ou de l'épisode, et où tu les as déjà vus.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.crop.circle", titre: "Qui est-ce ?",
                               detail: "Pendant un film ou un épisode du NAS sur l'Apple TV, mets en pause : les visages paraissent au-dessus de la barre, invités de l'épisode compris. Choisis-en un pour savoir dans quels films et séries vus tu l'as déjà croisé, et ce qui l'a fait connaître ; « Reprendre la lecture » ou Retour te ramène au film."),
            ]
        ),
        NoteVersion(
            numero: "8.8",
            date: "30 septembre 2026",
            resume: "L'iPhone, l'iPad et l'Apple TV mis d'accord, page par page ; la fiche s'ouvre sur une grande image, comme sur la TV.",
            fonctionnalites: [
                Fonctionnalite(symbole: "photo", titre: "La fiche, bord à bord",
                               detail: "Sur l'iPhone et l'iPad, la fiche s'ouvre sur une grande image sans texte, avec le logo du titre, comme sur l'Apple TV."),
                Fonctionnalite(symbole: "rectangle.expand.vertical", titre: "L'accueil plein écran",
                               detail: "Sur l'iPad en portrait aussi, avec l'affiche du titre. Les Nouveautés à droite portent leur rang."),
                Fonctionnalite(symbole: "appletv", titre: "L'Apple TV complétée",
                               detail: "La loupe ouvre la Recherche de l'iPhone : le clavier, puis les filtres et les résultats. « Autre date » dans Regarder ; dans Mes listes, le tri, « Regardable ce soir », cartes ou liste ; le nombre de propositions dans les Préférences ; les réglages à compléter."),
                Fonctionnalite(symbole: "externaldrive", titre: "Le NAS pareil partout",
                               detail: "Les mêmes rayons sur l'iPhone et la TV, les vides cachés ; « non reconnus » au bout des rangements."),
                Fonctionnalite(symbole: "paintpalette", titre: "La charte partout",
                               detail: "À venir en cartes communes, statistiques en blanc, plus d'orange sur ce qui ne se touche pas ; les saisons de la fiche TV sur leur ligne."),
            ]
        ),
        NoteVersion(
            numero: "8.7",
            date: "30 septembre 2026",
            resume: "« Pas ce genre » depuis la proposition de l'accueil, et des propositions rangées selon tes goûts ; les cartes se glissent comme les lignes d'une liste.",
            fonctionnalites: [
                Fonctionnalite(symbole: "hand.thumbsdown", titre: "Pas ce genre",
                               detail: "Le bouton ⋯ de la proposition (l'appui long sur l'Apple TV) : « Pas ce soir », « Pas ce genre », « Je n'aime pas ». Un genre écarté quitte l'accueil et les suggestions ; Préférences › Toi le repropose."),
                Fonctionnalite(symbole: "heart", titre: "Selon tes goûts",
                               detail: "Le top de l'année, dans la proposition, passe dans l'ordre de tes goûts : un genre que tu aimes remonte, un genre que tu évites descend."),
                Fonctionnalite(symbole: "play.rectangle", titre: "Comme Netflix",
                               detail: "La proposition occupe la page, avec « Lecture » et « Plus d'infos » ; les Nouveautés portent leur rang de popularité."),
                Fonctionnalite(symbole: "hand.draw", titre: "Glisser les cartes",
                               detail: "Sur toutes les pages en grille : « Ce soir », « Terminé », « Alertes » ou « Retirer », comme sur les lignes d'une liste."),
                Fonctionnalite(symbole: "square.grid.2x2", titre: "Cartes ou liste, Films et Séries",
                               detail: "Cartes ou liste sur Mes listes, Streaming, Nouveautés, Documentaires et le NAS ; Films et Séries à côté de « Filtres » dans Regarder."),
            ]
        ),
        NoteVersion(
            numero: "8.6",
            date: "28 septembre 2026",
            resume: "En tête de l'accueil, les propositions du soir défilent : on les fait glisser, et un toucher ouvre la fiche.",
            fonctionnalites: [
                Fonctionnalite(symbole: "rectangle.stack", titre: "Les propositions en carrousel",
                               detail: "Cinq propositions à faire glisser, ou « Autre chose » ; des points disent où tu en es. Sur le Mac, deux flèches au survol ; sur l'Apple TV, « Autre chose » et les points."),
                Fonctionnalite(symbole: "hand.tap", titre: "Un toucher ouvre la fiche",
                               detail: "Sur l'image ou le titre de la proposition ; sur l'Apple TV, le bouton « Fiche »."),
                Fonctionnalite(symbole: "heart", titre: "D'après tes goûts",
                               detail: "Après ta soirée, ce que tu as commencé et ta liste sur le NAS, des titres choisis d'après tes goûts, avant le top de l'année."),
                Fonctionnalite(symbole: "externaldrive", titre: "Le NAS d'abord, l'autre au choix",
                               detail: "Sur la fiche, le bouton principal lance le titre sur ton NAS s'il y est, sinon sur ta plateforme ; à côté, « Ailleurs » (ou le nom de l'autre source) propose de le regarder ailleurs."),
                Fonctionnalite(symbole: "calendar", titre: "Les jours pour toutes les sources",
                               detail: "Dans Regarder, la rangée de jours reste là aussi sur Streaming et le NAS, sur l'iPhone, l'iPad, le Mac et l'Apple TV : on y prévoit un titre pour un autre soir."),
                Fonctionnalite(symbole: "slider.horizontal.3", titre: "Combien de propositions",
                               detail: "1, 3, 5 ou 8, dans Préférences › Accueil ; le réglage suit sur tes autres appareils, Apple TV comprise."),
            ]
        ),
        NoteVersion(
            numero: "8.5",
            date: "28 septembre 2026",
            resume: "Une interface plus simple et la même partout : un seul sélecteur, un bouton principal qui dit où il mène, moins de commandes avant le contenu.",
            fonctionnalites: [
                Fonctionnalite(symbole: "capsule", titre: "Un seul sélecteur",
                               detail: "Partout des pastilles, la choisie en blanc : Regarder, Mes listes, la recherche, le NAS. L'orange ne sert plus qu'au bouton principal."),
                Fonctionnalite(symbole: "rectangle.stack", titre: "Moins de commandes",
                               detail: "Dans Regarder, les jours ne s'affichent que pour Tout et TV, comme sur l'Apple TV."),
                Fonctionnalite(symbole: "play.fill", titre: "Un bouton qui dit où",
                               detail: "« Choisir où regarder » quand il y a plusieurs sources ; « Tu l'as regardé ? » garde « Terminé » et range le reste sous « Pas encore »."),
                Fonctionnalite(symbole: "gearshape", titre: "Réglages jamais vides",
                               detail: "Sur l'iPad, le Mac et l'Apple TV, la page de droite montre d'emblée le premier réglage à compléter. Sur l'Apple TV, « Toi » est dans les Préférences."),
                Fonctionnalite(symbole: "wrench.and.screwdriver", titre: "Corrections",
                               detail: "Le titre de la page précédente ne se coupe plus sous le bouton retour ; le NAS ne range plus tout sous « Date inconnue »."),
            ]
        ),
        NoteVersion(
            numero: "8.4",
            date: "28 septembre 2026",
            resume: "Un film que Séance ne reconnaît pas seule dans TMDB s'identifie parmi ses propositions, sur l'iPhone, l'iPad, le Mac et l'Apple TV.",
            fonctionnalites: [
                Fonctionnalite(symbole: "questionmark.square.dashed", titre: "Identifier un titre",
                               detail: "Deux films du même nom la même année, un nom de fichier illisible : touche la vidéo non reconnue du NAS, ou le film non reconnu du guide TV, et choisis le bon titre parmi ce que TMDB propose. Toute l'œuvre le reprend — épisodes, copies, rediffusions."),
                Fonctionnalite(symbole: "arrow.triangle.2.circlepath", titre: "Retenu partout",
                               detail: "Le choix voyage avec la synchronisation et survit aux analyses du NAS. Dans Réglages › NAS et Réglages › TV, « Identifiés à la main » permet de le changer ou de l'oublier."),
            ]
        ),
        NoteVersion(
            numero: "8.3",
            date: "27 septembre 2026",
            resume: "Qui regarde avec toi ? Tes souvenirs sur l'accueil, l'épisode suivant des plateformes, l'image de tes vidéos, et les arrêts de Séance dans le journal.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.2", titre: "Qui regarde avec toi ?",
                               detail: "À la fin d'une lecture, après « Vu aujourd'hui » ou « Terminé », et au retour d'une plateforme : coche les personnes qui regardaient avec toi, le titre s'inscrit aussi chez elles. Sur l'Apple TV, la question se pose aussi avant de lancer."),
                Fonctionnalite(symbole: "play.tv", titre: "L'épisode suivant, même sur Netflix",
                               detail: "Ouvre une série sur une plateforme depuis Séance : au retour, « As-tu regardé Reacher S02E04 ? » coche l'épisode d'un geste. Aussi pour les films, sur l'iPhone, l'iPad, le Mac et l'Apple TV."),
                Fonctionnalite(symbole: "photo.on.rectangle", titre: "Tes souvenirs",
                               detail: "Sur l'accueil, tes dernières vidéos personnelles avec leur image : un clic et elle démarre ; « Tout voir » pour choisir. Dans « Couverture », choisis l'image qui représente une vidéo."),
                Fonctionnalite(symbole: "bolt.trianglebadge.exclamationmark", titre: "Les arrêts de Séance",
                               detail: "Si Séance s'arrête brusquement, Réglages › Journal le dit au lancement suivant, avec la page ouverte et le rapport du système ; sur l'Apple TV, dans À propos."),
            ]
        ),
        NoteVersion(
            numero: "8.2",
            date: "27 septembre 2026",
            resume: "Le nouvel accueil de l'Apple TV arrive sur l'iPhone, l'iPad et le Mac : de quoi regarder ce soir, les nouveautés, et reprendre.",
            fonctionnalites: [
                Fonctionnalite(symbole: "sparkles.tv", titre: "Ce soir, pour toi",
                               detail: "En grand, ta soirée prévue, sinon la vidéo entamée, un titre de ta liste sur le NAS ou le top de l'année ; « Reprendre à … » ou le bouton de la fiche, « Autre chose », « Pas ce soir »."),
                Fonctionnalite(symbole: "square.stack", titre: "Nouveautés",
                               detail: "À droite de la proposition sur l'iPad en paysage et le Mac ; en carrousel juste dessous sur l'iPhone et l'iPad en portrait."),
                Fonctionnalite(symbole: "play.rectangle.on.rectangle", titre: "Reprendre, ou des suggestions",
                               detail: "Les vidéos entamées ; s'il n'y en a pas, des suggestions d'après tes goûts. Le bandeau du haut et le salut laissent la place à la proposition."),
                Fonctionnalite(symbole: "person.crop.circle", titre: "Ton prénom sur l'Apple TV",
                               detail: "Dans Préférences › Toi : il remplace « Moi » partout sur la TV."),
            ]
        ),
        NoteVersion(
            numero: "8.1",
            date: "27 septembre 2026",
            resume: "Sur l'Apple TV, l'accueil propose de quoi regarder ce soir, avec les nouveautés à côté.",
            fonctionnalites: [
                Fonctionnalite(symbole: "sparkles.tv", titre: "Ce soir, pour toi",
                               detail: "En grand : ta soirée prévue, sinon la vidéo entamée, un titre de ta liste sur le NAS ou le top de l'année ; « Reprendre à … » ou « Regarder », « Autre chose » pour passer au suivant, « Pas ce soir » pour l'écarter jusqu'à demain."),
                Fonctionnalite(symbole: "square.stack", titre: "Nouveautés à côté",
                               detail: "Les trois plus récentes à droite de la proposition, et toutes les autres dans Regarder."),
                Fonctionnalite(symbole: "play.rectangle.on.rectangle", titre: "Reprendre, ou des suggestions",
                               detail: "Sous la proposition, les vidéos entamées ; s'il n'y en a pas, des suggestions tirées de tes goûts."),
            ]
        ),
        NoteVersion(
            numero: "8.0",
            date: "27 septembre 2026",
            resume: "Séance 8 à ce jour : une seule charte sur l'iPhone, l'iPad, le Mac et l'Apple TV, tes vidéos lues dans Séance, et chacun ses réglages dans la famille.",
            fonctionnalites: [
                Fonctionnalite(symbole: "rectangle.3.group", titre: "Une app, quatre écrans",
                               detail: "Trois onglets partout — Accueil, Regarder, Mes listes — et la loupe ; Regarder par jour ; les mêmes menus et les mêmes pages sur l'iPhone, l'iPad, le Mac et l'Apple TV."),
                Fonctionnalite(symbole: "play.rectangle", titre: "Tout se lit dans Séance",
                               detail: "Films, séries et souvenirs du NAS, directement : langue et sous-titres retenus, épisode suivant enchaîné, vu marqué tout seul, reprise là où tu t'es arrêté — et d'un toucher sur l'Apple TV."),
                Fonctionnalite(symbole: "person.2", titre: "Chacun chez soi",
                               detail: "Préférences à toi : goûts, réalisateurs, alertes, e-mail de la semaine et langue, pour chaque personne de la famille ; changer de personne est sûr."),
                Fonctionnalite(symbole: "person.crop.rectangle.stack", titre: "Réalisateurs",
                               detail: "Sur chaque fiche avec les acteurs ; on filtre la recherche par réalisateur et on le suit comme un acteur pour être prévenu de ses nouveaux films."),
                Fonctionnalite(symbole: "sparkles", titre: "Un accueil à jour",
                               detail: "Les plus récents d'abord, les derniers téléchargements du NAS en tête, les alertes à lire sous la cloche."),
            ]
        ),
        NoteVersion(
            numero: "7.0",
            date: "25 septembre 2026",
            resume: "Un nouveau menu, le même partout, et tes films du NAS lus dans Séance.",
            fonctionnalites: [
                Fonctionnalite(symbole: "list.bullet", titre: "Un menu clair",
                               detail: "Streaming, TV et NAS ont chacun leur entrée ; des Réglages en une seule liste."),
                Fonctionnalite(symbole: "play.tv", titre: "Le lecteur de Séance",
                               detail: "Les films du NAS se lisent dans l'app, en plein écran."),
            ]
        ),
        NoteVersion(
            numero: "6.0",
            date: "21 septembre 2026",
            resume: "La famille, tes souvenirs en albums, et une Apple TV qui fait comme l'iPhone.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.2", titre: "La famille",
                               detail: "Un profil par personne, sur tous tes appareils."),
                Fonctionnalite(symbole: "photo.on.rectangle", titre: "Tes souvenirs",
                               detail: "Les vidéos personnelles du NAS en albums, avec leur image ; tous les formats se lisent."),
                Fonctionnalite(symbole: "link", titre: "Droit au titre",
                               detail: "« Regarder » ouvre le film sur Netflix, Apple TV ou Disney+, et la chaîne en direct dans blue TV."),
            ]
        ),
        NoteVersion(
            numero: "5.0",
            date: "20 septembre 2026",
            resume: "L'e-mail de la semaine, un accueil en grandes cartes et les documentaires.",
            fonctionnalites: [
                Fonctionnalite(symbole: "envelope", titre: "L'e-mail de la semaine",
                               detail: "Ce qui sort et ce qui passe pour tes titres, dans ta boîte, le jour choisi."),
                Fonctionnalite(symbole: "rectangle.grid.1x2", titre: "Grandes cartes",
                               detail: "Un accueil plus visuel, « Aujourd'hui » d'un coup d'œil, et les documentaires."),
            ]
        ),
        NoteVersion(
            numero: "4.0",
            date: "20 septembre 2026",
            resume: "Séance arrive sur l'Apple TV.",
            fonctionnalites: [
                Fonctionnalite(symbole: "appletv", titre: "Sur la télévision",
                               detail: "L'Apple TV se configure avec un code depuis l'iPhone, et tes listes y arrivent par le NAS."),
                Fonctionnalite(symbole: "hand.thumbsup", titre: "Les pouces",
                               detail: "Dis ce qui te plaît sans l'avoir vu : tes suggestions te ressemblent davantage."),
            ]
        ),
        NoteVersion(
            numero: "3.0",
            date: "18 septembre 2026",
            resume: "Tes appareils se tiennent à jour entre eux, même hors ligne.",
            fonctionnalites: [
                Fonctionnalite(symbole: "arrow.triangle.2.circlepath", titre: "Synchronisation",
                               detail: "iPhone, iPad et Mac partagent tes listes par iCloud Drive, suppressions comprises."),
                Fonctionnalite(symbole: "iphone.and.arrow.forward", titre: "Nouvel appareil",
                               detail: "Prêt en trois étapes."),
            ]
        ),
        NoteVersion(
            numero: "2.0",
            date: "17 septembre 2026",
            resume: "Des suggestions pour ce soir selon tes goûts, et des soirées à prévoir.",
            fonctionnalites: [
                Fonctionnalite(symbole: "moon.stars", titre: "Ce soir",
                               detail: "Des suggestions qui te ressemblent, et un film ou une série prévu pour le soir de ton choix."),
                Fonctionnalite(symbole: "square.and.arrow.up", titre: "Sauvegarde",
                               detail: "Tout passe d'un appareil à l'autre."),
            ]
        ),
        NoteVersion(
            numero: "1.0",
            date: "16 septembre 2026",
            resume: "Les débuts : où regarder en Suisse, le suivi des séries, le NAS et les alertes.",
            fonctionnalites: [
                Fonctionnalite(symbole: "magnifyingglass", titre: "Où regarder",
                               detail: "Chaque film et chaque série, sur tes plateformes et à la TV."),
                Fonctionnalite(symbole: "bell", titre: "Suivi et alertes",
                               detail: "Épisodes, sorties et passages à la TV ; statistiques, widgets, Siri et le Mac."),
            ]
        ),
    ]
}

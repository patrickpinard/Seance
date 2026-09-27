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

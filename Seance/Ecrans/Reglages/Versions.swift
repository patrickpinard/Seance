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
            numero: "8.2.1",
            date: "26 septembre 2026",
            resume: "La page d'un acteur sans roue dentée, et la barre d'avancement de l'Apple TV qui garde sa taille.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.crop.rectangle", titre: "La page d'un acteur",
                               detail: "Plus de roue des réglages en haut : la cloche et « Dans la recherche » suffisent. Ouverte depuis tes Préférences, « Dans la recherche » referme d'abord la feuille — l'onglet changeait derrière elle, et rien ne semblait se passer."),
                Fonctionnalite(symbole: "clock", titre: "La bonne heure d'installation",
                               detail: "À propos et Versions disent enfin le jour et l'heure où la version est arrivée sur l'appareil — et non plus le 1er janvier 1970 : iOS remet à zéro les dates des fichiers installés, l'heure est maintenant inscrite dans l'app à l'installation."),
                Fonctionnalite(symbole: "slider.horizontal.below.rectangle", titre: "La barre d'avancement de la TV",
                               detail: "Elle garde sa taille quand on y va et quand on clique dessus : tvOS l'agrandissait sur toute la largeur."),
            ]
        ),
        NoteVersion(
            numero: "8.2",
            date: "26 septembre 2026",
            resume: "La même interface sur l'iPad, le Mac et l'iPhone : le portrait et la roue en haut de chaque page. Le son du lecteur a son bouton, et l'e-mail de la semaine ouvre Séance.",
            fonctionnalites: [
                Fonctionnalite(symbole: "gearshape", titre: "La roue en haut de chaque page",
                               detail: "Sur l'iPad et le Mac comme sur l'iPhone : Réglages à la roue dentée en haut à droite de chaque page, et à gauche le portrait avec le prénom de qui regarde, qui ouvre les Préférences. Le menu ne garde que Accueil, Regarder, Mes listes et la loupe."),
                Fonctionnalite(symbole: "speaker.wave.2", titre: "Le son, à part",
                               detail: "Dans le lecteur, un bouton haut-parleur ouvre le volume, debout, et coupe le son d'un toucher ; AirPlay a son propre bouton. Plus de second curseur qu'on prenait pour la barre d'avancement."),
                Fonctionnalite(symbole: "envelope.open", titre: "L'e-mail ouvre Séance",
                               detail: "Dans l'e-mail de la semaine, le titre ou l'affiche d'un film ouvre sa fiche dans Séance, sur l'iPhone, l'iPad ou le Mac — et non plus la page de TMDB."),
            ]
        ),
        NoteVersion(
            numero: "8.1",
            date: "26 septembre 2026",
            resume: "Les séries s'enchaînent, les films se marquent vus tout seuls, ta langue est retenue — et une vidéo commencée sur l'iPhone continue sur l'Apple TV d'un toucher.",
            fonctionnalites: [
                Fonctionnalite(symbole: "forward.end", titre: "L'épisode suivant, tout seul",
                               detail: "À la fin d'un épisode du NAS, le suivant démarre après dix secondes — « Épisode suivant » est proposé dès le générique. Sur l'iPhone, l'iPad et l'Apple TV."),
                Fonctionnalite(symbole: "checkmark.circle", titre: "Vu, sans question",
                               detail: "Au-delà de 90 % d'un film ou d'un épisode (ou dans le générique d'un long film), il est marqué vu : l'historique et le suivi des séries se remplissent seuls."),
                Fonctionnalite(symbole: "captions.bubble", titre: "Ta langue et tes sous-titres, retenus",
                               detail: "Réglages › Lecture : la langue voulue (français, VO…) et quand mettre les sous-titres. Le lecteur les choisit à chaque film, pour la personne qui regarde."),
                Fonctionnalite(symbole: "appletv", titre: "Sur l'Apple TV, d'un toucher",
                               detail: "Dans le lecteur de l'iPhone, « Sur l'Apple TV » envoie la vidéo à Séance ouverte sur la TV, à la seconde où tu en es. La demande est signée : un inconnu du réseau ne peut rien lancer."),
                Fonctionnalite(symbole: "antenna.radiowaves.left.and.right", titre: "Hors de la maison",
                               detail: "Sur le réseau mobile, Séance le dit, et emploie l'adresse du NAS par ton VPN ou Tailscale si tu l'as indiquée dans Réglages › NAS."),
                Fonctionnalite(symbole: "play.circle", titre: "Le widget « Reprendre »",
                               detail: "Sur l'écran d'accueil, les films et épisodes entamés avec leur progression ; un toucher reprend là où tu t'étais arrêté."),
                Fonctionnalite(symbole: "tv", titre: "L'Apple TV plus directe",
                               detail: "La TV lit le NAS en SMB, sans relais : plus rapide. Gauche et droite pendant la lecture avancent ou reculent, de plus en plus vite si l'on insiste. Réglages en deux colonnes, sans changer de page. « Terminé » se défait d'un clic. Sur la page d'un acteur, un seul bouton, et l'appui long pour les choix."),
                Fonctionnalite(symbole: "bolt", titre: "Plus rapide, plus légère",
                               detail: "Les images en mémoire sont limitées à 150 Mo et téléchargées une seule fois ; le guide TV et le NAS se lisent en même temps au démarrage ; les nouveautés Streaming de la TV sont gardées quatre heures."),
                Fonctionnalite(symbole: "clock", titre: "L'heure d'installation",
                               detail: "À propos et Versions disent le jour et l'heure où chaque version est arrivée sur l'appareil."),
                Fonctionnalite(symbole: "play.tv", titre: "Netflix sur l'Apple TV",
                               detail: "Séance attend l'identifiant exact du titre avant d'ouvrir Netflix. Depuis septembre 2025, l'app Netflix de tvOS semble ignorer ces liens : Réglages › À propos › « Essai des liens Netflix » dit lequel marche encore chez toi."),
            ]
        ),
        NoteVersion(
            numero: "8.0",
            date: "25 septembre 2026",
            resume: "Une seule charte pour l'iPhone, l'iPad, le Mac et l'Apple TV : trois onglets, Regarder par jour, des cartes allégées, une fiche qui va à l'essentiel — et tes films reprennent là où tu t'étais arrêté.",
            fonctionnalites: [
                Fonctionnalite(symbole: "rectangle.3.group", titre: "Trois onglets, partout",
                               detail: "Accueil, Regarder, Mes listes et la loupe, la même barre sur les quatre appareils. En haut de chaque page, ton portrait à gauche (tes préférences) et la roue des réglages à droite — une seule par page."),
                Fonctionnalite(symbole: "calendar", titre: "Regarder, jour par jour",
                               detail: "Ce soir, le programme TV, tes plateformes et ton NAS sont réunis dans Regarder. La rangée commence par « Auj. » : ta soirée, des suggestions, ce qui passe à la TV ; un autre jour sert à planifier. Tout · Streaming · TV · NAS en pastilles."),
                Fonctionnalite(symbole: "line.3.horizontal.decrease", titre: "Les filtres d'Explorer dans Regarder",
                               detail: "Catégorie (films, séries, documentaires), genres — un appui long exclut —, période, durée, acteurs, note, langue, déjà vus, tri, et tes filtres enregistrés. Sur l'Apple TV, en deux parties : les filtres à gauche, les résultats à droite, à chaque choix."),
                Fonctionnalite(symbole: "arrow.counterclockwise.circle", titre: "Reprendre où tu en étais",
                               detail: "Un film ou une vidéo du NAS arrêté au milieu repart là où tu l'as laissé, sur n'importe quel appareil : « Reprendre à 1:03:12 » sur la fiche, une rangée « Reprendre » sur l'accueil et dans l'étagère de l'Apple TV. « Depuis le début » reste à portée."),
                Fonctionnalite(symbole: "pip.enter", titre: "Continuer dans Séance",
                               detail: "Dans le lecteur de l'iPhone et de l'iPad, deux boutons : la croix arrête la lecture ; « Continuer dans Séance » passe la vidéo dans une petite fenêtre et te rend l'app — films, séries et souvenirs."),
                Fonctionnalite(symbole: "play.rectangle", titre: "Une fiche qui va à l'essentiel",
                               detail: "Un bouton principal qui dit ce qu'il fait — « Regarder sur Prime Video », « Reprendre à… » —, puis Ma liste, Ce soir et « ⋯ » pour le reste. « Ton avis » : les pouces et l'étoile, dans le même trait que les autres icônes. Le même ordre sur l'Apple TV."),
                Fonctionnalite(symbole: "rectangle.on.rectangle", titre: "Des cartes qui se lisent d'un coup d'œil",
                               detail: "Une ligne d'origine, le titre, une ligne de faits et le ▶︎ blanc. Glisser vers la gauche une carte de ta soirée propose « Un autre soir » et « Retirer » ; l'appui long, les mêmes gestes et « Terminé »."),
                Fonctionnalite(symbole: "paintpalette", titre: "Une charte, vérifiée",
                               detail: "Sombre seulement, l'orange réservé à ce qui se touche, des SF Symbols d'un seul trait, « Suggestions » partout, plus d'emoji ni de phrases sous les titres. Les réglages de l'iPad et du Mac s'ouvrent en deux colonnes ; ceux de l'Apple TV en liste, avec un aperçu. Un test refuse désormais toute couleur ou taille de texte en dur."),
                Fonctionnalite(symbole: "appletv", titre: "L'Apple TV, page par page",
                               detail: "Ce qui est choisi en blanc ; Regarder avec les logos des plateformes, la TV en direct et en horaires, le NAS par mois d'ajout et ses rayons Films · Séries · Documentaires · Vidéos ; les filtres en liste comme les Réglages ; une vraie recherche au clavier ; l'acteur, les Préférences et les Statistiques repensés. L'appui long sur une carte : Regarder, Voir la fiche, Un autre soir, Terminé, Retirer de Reprendre. Le lecteur a ses commandes : la bande de progression, ±10 s, la langue et les sous-titres."),
                Fonctionnalite(symbole: "envelope", titre: "L'e-mail se règle une fois",
                               detail: "Le serveur, le compte et les destinataires de l'e-mail de la semaine suivent désormais tes changements sur tous tes appareils. Le mot de passe, lui, ne voyage que par l'envoi chiffré « Envoyer à un appareil »."),
            ]
        ),
        NoteVersion(
            numero: "7.0",
            date: "25 septembre 2026",
            resume: "Un nouveau menu, le même partout : Streaming, TV et NAS y ont chacun leur entrée. Des Réglages en une liste, et tes films du NAS lus dans Séance, à l'horizontale, avec le son, les langues et les sous-titres.",
            fonctionnalites: [
                Fonctionnalite(symbole: "menubar.rectangle", titre: "Streaming, TV, NAS dans le menu",
                               detail: "Sur l'iPad, le Mac et l'Apple TV, la même barre : Accueil, Ce soir, Streaming, TV, NAS, Mes listes, puis la loupe et la roue dentée. Sur l'iPhone, les trois sources se partagent l'onglet « Regarder ». Streaming est une page neuve : ce que tes abonnements proposent de nouveau, plateforme par plateforme."),
                Fonctionnalite(symbole: "person.crop.circle", titre: "Préférences au portrait",
                               detail: "Tes goûts, tes notes et tes statistiques s'ouvrent par le portrait, en haut à gauche de chaque page, au lieu d'occuper un onglet."),
                Fonctionnalite(symbole: "list.bullet", titre: "Les Réglages en une liste",
                               detail: "Une ligne par réglage, sa valeur à droite, un point vert ou orange pour ce que Séance surveille, rangés en quatre groupes : Où regarder, Toi, La maison, L'app. Tout tient en un écran et demi au lieu de six. Le bouton « Synchroniser » prend sa taille normale, à côté du geste du moment."),
                Fonctionnalite(symbole: "tv", titre: "« TV » partout",
                               detail: "« Télé » et « Télévision » deviennent « TV » dans tous les textes, sur tous les appareils."),
                Fonctionnalite(symbole: "play.rectangle.fill", titre: "VLCKit par défaut, Infuse au choix",
                               detail: "Réglages › Lecture propose Séance (VLCKit), réglage d'origine, ou Infuse. VLCKit lit directement sur le NAS, sans relais : plus rapide au démarrage comme en cours de lecture."),
                Fonctionnalite(symbole: "rectangle.landscape.rotate", titre: "Le lecteur de l'iPhone, à l'horizontale",
                               detail: "Le film passe à l'horizontale et suit l'iPhone ; un sablier dit où en est le chargement ; les commandes et la croix s'effacent au bout de trois secondes, un toucher les ramène. Le volume et AirPlay sont sous la barre, et un menu choisit la langue, les sous-titres, la vitesse et le cadrage."),
            ]
        ),
        NoteVersion(
            numero: "6.6",
            date: "25 septembre 2026",
            resume: "Les films du NAS se lisent dans Séance sur l'iPad et l'Apple TV, Netflix ouvre le bon titre sur la TV, et ce qui passe en direct se lance d'un clic dans blue TV.",
            fonctionnalites: [
                Fonctionnalite(symbole: "play.rectangle.fill", titre: "Les films du NAS, dans Séance",
                               detail: "Sur l'iPhone, l'iPad et l'Apple TV, un film ou un épisode du NAS s'ouvre dans le lecteur de Séance, par le moteur de VLC — y compris les MKV. Sur l'iPad, VLC lancé de l'extérieur restait bloqué ; ce n'est plus lui qui lit. Le Mac garde Infuse."),
                Fonctionnalite(symbole: "arrow.uturn.backward", titre: "Retour là où tu étais, sur l'Apple TV",
                               detail: "Une vidéo personnelle ou un film du NAS se lit dans Séance, et la touche Retour ramène à la page d'où tu l'as lancé. Avant, Infuse lisait, et on restait chez lui."),
                Fonctionnalite(symbole: "play.tv.fill", titre: "Netflix ouvre le bon film, sur la TV",
                               detail: "Sur tvOS, le lien universel de Netflix n'ouvre que sa page d'accueil. Séance passe maintenant par l'adresse de l'app (nflx://) avec l'identifiant exact du titre ; Disney+ de même. Si l'app refuse, Séance essaie l'adresse suivante, puis la recherche."),
                Fonctionnalite(symbole: "dot.radiowaves.left.and.right", titre: "En ce moment sur tes chaînes",
                               detail: "Sur l'accueil de l'Apple TV, une étagère montre les films et séries en cours sur tes chaînes, avec le temps qui reste. Un clic, et blue TV s'ouvre sur la chaîne, en direct. « Ce soir à la TV » ne garde que ce qui est à venir."),
                Fonctionnalite(symbole: "sun.max", titre: "Bonjour ou Bonsoir",
                               detail: "L'e-mail de la semaine salue selon l'heure de l'envoi : « Bonjour » avant 18 h, « Bonsoir » ensuite."),
            ]
        ),
        NoteVersion(
            numero: "6.5",
            date: "24 septembre 2026",
            resume: "Séance lit désormais tout elle-même — AVI, WMV, MKV compris — et ne renvoie plus vers Infuse ou VLC.",
            fonctionnalites: [
                Fonctionnalite(symbole: "play.rectangle.on.rectangle.fill", titre: "Le moteur de VLC, dans Séance",
                               detail: "L'iPhone, l'iPad et l'Apple TV embarquent VLCKit : les AVI de caméscope, les WMV, les MKV, le DV et le MJPEG se lisent dans Séance, depuis le NAS, sans rien copier et sans passer la main. Le lecteur d'Apple reste aux commandes pour ce qu'il sait lire — il est plus léger et donne AirPlay et l'image dans l'image. Sur le Mac, où Infuse fonctionne déjà, Séance garde le lecteur d'Apple : VLCKit n'existe pas pour Mac Catalyst."),
                Fonctionnalite(symbole: "arrow.uturn.backward.circle", titre: "Infuse et VLC te ramènent ici",
                               detail: "Quand la lecture se termine dans une app extérieure, elle rouvre Séance au lieu de te laisser devant sa bibliothèque. Un film ouvert dans la bibliothèque d'Infuse fait exception : cette adresse-là n'accepte aucun retour."),
                Fonctionnalite(symbole: "film.stack", titre: "Tes vidéos converties",
                               detail: "Un outil à part (outils/analyser-videos.sh, outils/convertir-videos.sh) inventorie le NAS et transforme en MP4 ce qu'aucun iPhone ne lit. Mesuré : un AVI de 1,1 Go devient 27 Mo, sans différence visible. L'original n'est jamais effacé."),
                Fonctionnalite(symbole: "bell.badge.waveform", titre: "Les alertes reçues se retrouvent",
                               detail: "Réglages › Alertes › « Alertes reçues » : ce que Séance t'a envoyé, et ce qu'elle enverra. Une notification balayée ne laissait aucune trace ; chaque ligne ouvre maintenant la fiche du titre."),
                Fonctionnalite(symbole: "creditcard", titre: "« Tu n'es pas abonné à cette plateforme »",
                               detail: "Un titre qui n'est que sur Netflix ou Apple TV+ alors que tu n'y es pas abonné ne se dit plus introuvable : Séance le montre, et propose de s'y abonner ou de cocher la plateforme si tu l'es déjà."),
                Fonctionnalite(symbole: "play.circle", titre: "Le ▶︎ dans la liste détaillée",
                               detail: "Mes listes en mode liste n'avait pas de bouton de lecture, alors que les grandes cartes l'ont depuis la 6.1."),
                Fonctionnalite(symbole: "textformat", titre: "« Perso » devient « Vidéos »",
                               detail: "Le rayon du NAS porte le nom de ce qu'il contient. Et dans le lecteur, la croix a quitté le coin du volume et d'AirPlay : elle descend sous eux, et un glissement vers le bas ferme aussi."),
            ]
        ),
        NoteVersion(
            numero: "6.4",
            date: "24 septembre 2026",
            resume: "Ton NAS se range par ajouts, par année et par genre, ses films se lancent enfin d'un toucher, et tes souvenirs montrent leur vraie image.",
            fonctionnalites: [
                Fonctionnalite(symbole: "square.grid.2x2", titre: "Trois façons de ranger ton NAS",
                               detail: "« Ajouts » montre ce qui vient d'arriver, mois par mois, d'après la date du fichier sur le NAS ; « Année » range par année de sortie ; « Genre » par genre TMDB, le mieux fourni d'abord. « A→Z » reste le rangement d'origine. Le choix est retenu d'une fois sur l'autre."),
                Fonctionnalite(symbole: "play.circle.fill", titre: "Le ▶︎ sur les films du NAS",
                               detail: "La page « Sur ton NAS » dessinait ses propres cartes, sans bouton de lecture : cinquante films lançables, et rien pour les lancer. Elle utilise maintenant la carte commune de l'app — donc le ▶︎, les logos des plateformes, et la même mise en page que partout ailleurs."),
                Fonctionnalite(symbole: "photo.stack", titre: "Tes souvenirs montrent ce qu'ils contiennent",
                               detail: "Séance tire la première image de chaque vidéo — une seconde après le début, pour éviter le noir — et la pose sur sa carte. Les douze « GOPR00xx » d'un album deviennent douze scènes reconnaissables. L'image est lue une fois puis gardée sur l'appareil ; un AVI ou un WMV, dont iOS ne tire rien, garde son icône."),
                Fonctionnalite(symbole: "rectangle.grid.2x2", titre: "Deux colonnes et une recherche",
                               detail: "Quarante souvenirs en cartes pleine largeur demandaient quarante écrans de défilement. Ils tiennent maintenant deux par ligne sur l'iPhone, avec un champ de recherche par nom d'album ou de vidéo, et les tirets des noms de fichiers deviennent des espaces."),
                Fonctionnalite(symbole: "play.rectangle.on.rectangle", titre: "La série du NAS se lance de sa carte",
                               detail: "Comme sur l'Apple TV : le ▶︎ d'une série lance le premier épisode que tu n'as pas vu, et le bouton dit lequel — « Regarder S01E03 »."),
                Fonctionnalite(symbole: "checklist", titre: "Les dossiers du NAS se cochent",
                               detail: "Séance lit les dossiers du partage et les propose à cocher, au lieu de les faire taper séparés par des virgules — « Films, NEW, SériesFilms, Séries » était vite arrivé."),
                Fonctionnalite(symbole: "cart.fill", titre: "« À louer » mène enfin quelque part",
                               detail: "Un film qui n'est sur aucune de tes plateformes affichait « À louer ou acheter » sans rien proposer. Un bouton ouvre maintenant la boutique qui le loue."),
                Fonctionnalite(symbole: "person.2.circle", titre: "« Qui regarde ? » là où c'est utile",
                               detail: "L'écran s'affichait à chaque ouverture, même sur ton iPhone où la réponse ne change jamais. Il ne s'invite plus que sur les appareils partagés — l'iPad, le Mac, l'Apple TV — et reste réglable dans Réglages › Famille. Chaque personne a aussi sa couleur : deux profils au même symbole ne se ressemblent plus."),
                Fonctionnalite(symbole: "xmark.circle", titre: "Le lecteur ne se bat plus avec AirPlay",
                               detail: "La croix « Fermer » était posée sur le bouton AirPlay du lecteur d'Apple : un toucher partait au hasard sur l'un ou sur l'autre. Elle est passée à droite. Et une vidéo que VLC refusait d'ouvrir en SMB est maintenant essayée par sa seconde adresse, celle que VLC annonce."),
                Fonctionnalite(symbole: "command", titre: "⌘[ pour revenir, sur le Mac",
                               detail: "Le raccourci manquait alors que ⌘1 à ⌘6, ⌘F et ⌘, existaient. Sur l'Apple TV, les cartes ne portent plus que deux logos : à trois mètres, quatre pastilles empilées ne se lisaient plus."),
            ]
        ),
        NoteVersion(
            numero: "6.3",
            date: "22 septembre 2026",
            resume: "L'Apple TV rattrape l'iPhone : les logos des plateformes sur les cartes, des menus enfin lisibles, le lancement dans blue TV et l'historique des versions.",
            fonctionnalites: [
                Fonctionnalite(symbole: "play.tv.fill", titre: "Les logos sur les cartes de la TV",
                               detail: "Netflix, Disney+, Prime Video, la télé, le NAS : les mêmes petites pastilles que sur l'iPhone, en haut de chaque grande carte. L'Apple TV partage maintenant « Où regarder » avec l'app, au lieu de s'en passer."),
                Fonctionnalite(symbole: "rectangle.on.rectangle", titre: "Des menus lisibles",
                               detail: "Les questions de la TV — « Tu l'as regardé ? », le choix de la source — passent par une page de Séance, avec ses couleurs : les fenêtres du système écrivaient parfois en blanc sur blanc. Les pages de réglage aussi : fond opaque, et chaque champ garde son libellé au-dessus, même rempli."),
                Fonctionnalite(symbole: "tv.badge.wifi", titre: "Le lancement dans blue TV",
                               detail: "Séance demande à Swisscom l'émission en cours sur la chaîne, puis ouvre blue TV dessus ; sans l'app, le lecteur web prend le relais. Un film ne se lance sur une chaîne que pendant sa diffusion."),
                Fonctionnalite(symbole: "hourglass", titre: "On sait enfin ce que Séance attend",
                               detail: "Lancer un film sur Netflix, Disney+ ou blue TV demandait plusieurs secondes sans un mot : Séance interroge Wikidata pour retrouver la page exacte du titre. Un sablier le dit maintenant, avec ce qu'il fait — et l'attente est bornée à deux secondes et demie, après quoi la plateforme s'ouvre sur sa recherche ; la réponse en retard sert la fois suivante."),
                Fonctionnalite(symbole: "square.grid.2x2", titre: "« Vidéos » est un rayon du NAS",
                               detail: "Sur ton NAS : Films, Séries, NEW et Vidéos, du même geste — tes souvenirs ne sont plus derrière une tuile à part. « Non reconnus » n'est plus une case du sélecteur mais une petite puce sous le résumé : c'est de l'entretien, pas un rayon."),
                Fonctionnalite(symbole: "speaker.wave.2.fill", titre: "Le son de tes vidéos personnelles",
                               detail: "Le lecteur de Séance déclare enfin son audio comme un lecteur : le son sort même quand le commutateur de l'iPhone est sur silencieux, et il continue quand la musique tournait. Et si la vidéo porte un son qu'iOS ne décode pas (de l'AC-3, souvent), Séance le dit et propose de l'ouvrir là où elle s'entend. Une vidéo qui ne part pas dit enfin pourquoi : « du MPEG-4 Part 2 (Xvid ou DivX) », plutôt qu'un écran noir de douze secondes."),
                Fonctionnalite(symbole: "list.bullet.rectangle", titre: "L'historique des versions partout",
                               detail: "Réglages › À propos › « Ce que chaque version a apporté » : la même liste que sur l'iPhone, dépliable à la télécommande."),
            ]
        ),
        NoteVersion(
            numero: "6.2",
            date: "22 septembre 2026",
            resume: "Tes vidéos personnelles deviennent des albums de souvenirs, chacun avec son icône — et une vidéo que Séance ne sait pas lire part d'elle-même dans Infuse ou VLC.",
            fonctionnalites: [
                Fonctionnalite(symbole: "rectangle.stack.fill", titre: "Des albums de souvenirs",
                               detail: "Chaque dossier d'événement du NAS (« 2026 › Vacances d'été ») devient un album : une grande carte 16/9 avec son icône, ses dates et ses vidéos, rangée par année. Une vidéo seule, hors dossier, fait carte à elle seule et se lance d'un toucher. Dans l'album, les vidéos se suivent dans l'ordre où elles ont été filmées."),
                Fonctionnalite(symbole: "wand.and.stars", titre: "L'icône devinée d'après le nom",
                               detail: "« Anniversaire de Camille » : un gâteau ; « Ski à Verbier » : un skieur ; « Noël » : un sapin. Vingt-quatre icônes — naissance, mariage, vacances, voyage, montagne, école, spectacle, animaux… —, toutes celles de la charte, en orange."),
                Fonctionnalite(symbole: "photo.badge.checkmark", titre: "La feuille « Couverture »",
                               detail: "Un appui long (clic droit sur le Mac), ou le crayon d'un album : l'icône, le titre et la date. Pour une vidéo, « Pour tout l'album » donne l'icône à l'album entier ; « Rétablir » revient à ce que Séance propose. Tes choix voyagent entre tes appareils, Apple TV comprise, le plus récent l'emportant."),
                Fonctionnalite(symbole: "calendar", titre: "La bonne année",
                               detail: "La date d'un fichier est souvent celle de sa copie sur le NAS : quand elle contredit l'année du dossier (« 2025 › Ski », copié en 2026), c'est l'année du dossier qui compte."),
                Fonctionnalite(symbole: "play.circle", titre: "Une vidéo qui ne se lit pas ici part ailleurs",
                               detail: "Le lecteur de Séance vérifie qu'une vidéo démarre vraiment ; sinon — un codec qu'iOS ne décode pas —, il se referme et la vidéo s'ouvre dans l'app de Réglages › Lecture, puis dans l'autre si la première n'est pas installée. Avant, l'écran restait noir, et l'alerte qui proposait VLC restait cachée derrière le lecteur. Sur l'Apple TV aussi : Infuse, puis VLC."),
                Fonctionnalite(symbole: "appletv", titre: "Apple TV : les mêmes albums",
                               detail: "Rangés par année, en grandes cartes à icône ; un album s'ouvre sur ses vidéos, une vidéo seule se lance d'un clic. VoiceOver lit maintenant le titre des cartes et des tuiles de la TV."),
            ]
        ),
        NoteVersion(
            numero: "6.1.1",
            date: "22 septembre 2026",
            resume: "Un bouton ▶︎ sur chaque grande carte et en tête de fiche : on voit enfin comment lancer un film — et Séance demande où, quand il est à plusieurs endroits.",
            fonctionnalites: [
                Fonctionnalite(symbole: "play.circle.fill", titre: "▶︎ sur les cartes",
                               detail: "Accueil, listes, NAS, Explorer : une grande carte porte un rond ▶︎ en bas à droite quand le titre se lance d'ici — le fichier du NAS, la plateforme (le titre lui-même, comme Kill Bill sur Netflix), la chaîne en direct dans blue TV. Toucher la carte ailleurs ouvre toujours la fiche."),
                Fonctionnalite(symbole: "play.rectangle.fill", titre: "▶︎ en tête de fiche",
                               detail: "Une capsule orange, sous le titre : « ▶︎ Netflix », « ▶︎ Sur ton NAS » — ou « ▶︎ Lecture ▾ » quand il faut choisir. Les autres accès (un passage TV à venir) restent à côté. À la TV, le ▶︎ n'apparaît que pendant la diffusion, ou dans le quart d'heure qui la précède : blue TV n'ouvre que le direct."),
                Fonctionnalite(symbole: "list.bullet", titre: "Plusieurs accès ? Séance demande",
                               detail: "Un titre sur ton NAS et sur Netflix, ou sur deux plateformes : ▶︎ et « Regarder… » ouvrent la liste des accès, et tu choisis. Pareil sur la carte d'une soirée et sur l'Apple TV."),
                Fonctionnalite(symbole: "appletv", titre: "Apple TV : lancer d'abord",
                               detail: "En tête de fiche, « Lire » pour le NAS — le prochain épisode d'une série aussi —, « Regarder sur Netflix » pour une plateforme, ou « Regarder… » pour choisir. « Marquer vu » devient « Terminé », comme sur l'iPhone."),
            ]
        ),
        NoteVersion(
            numero: "6.1",
            date: "22 septembre 2026",
            resume: "« Regarder » ouvre le titre lui-même sur Netflix, Apple TV et Disney+, et la chaîne en direct dans blue TV ; « Terminé » d'un geste, Terminés par mois ; un film vu ensemble s'inscrit chez chacun.",
            fonctionnalites: [
                Fonctionnalite(symbole: "play.fill", titre: "Le titre lui-même, plus sa recherche",
                               detail: "Sur Netflix, Apple TV et Disney+, « Regarder » ouvre la page du titre — un film Netflix se lance directement, un film Apple TV+ aussi. Séance trouve l'identifiant de chaque titre chez ces plateformes dans Wikidata, base publique et gratuite : sans clé ni compte, et rien de personnel ne part avec la demande. Un titre inconnu de Wikidata garde la recherche de la plateforme. Prime Video aussi : Wikidata n'y connaît que les références d'Amazon.com, introuvables en Suisse."),
                Fonctionnalite(symbole: "play.tv.fill", titre: "La chaîne en direct dans blue TV",
                               detail: "Quand un titre passe en ce moment à la TV, ou dans le quart d'heure, son bouton devient « RTS 1 en direct · blue TV » : l'app blue TV de Swisscom s'ouvre sur la chaîne, sur l'iPhone, l'iPad et l'Apple TV ; sur le Mac, le lecteur web tv.blue.ch. Réglages › Télévision › « Ouvrir les chaînes dans blue TV » l'éteint. Swisscom n'a pas d'API publique : ni replay ni enregistrement."),
                Fonctionnalite(symbole: "checkmark", titre: "« Terminé », d'un geste",
                               detail: "Sur la fiche d'un film, l'œil devient « Terminé » : un toucher, et le film rejoint tes Terminés, daté du jour (appui long : « Déjà vu avant », hors statistiques). Sur la carte d'une soirée aussi. Une série finie chez TMDB a son bouton « Terminé », qui coche les épisodes restants."),
                Fonctionnalite(symbole: "checkmark.rectangle.stack", titre: "Les séries finies se rangent seules",
                               detail: "Le dernier épisode vu d'une série terminée ou annulée la range dans Terminés ; tant qu'une série continue, elle reste « En cours », même à jour. Les séries déjà vues jusqu'au bout se rangent au prochain calcul des alertes ou en ouvrant leur fiche. Décocher un épisode la remet en cours."),
                Fonctionnalite(symbole: "calendar", titre: "Terminés, par mois",
                               detail: "Septembre 2026, août 2026… : chaque titre sous le mois où tu l'as fini, avec le compte du mois — « 3 films · 1 série · 7 h 40 ». Ce qui n'a pas de date (« déjà vu avant ») va dans « Plus tôt ». Les tris par titre ou par durée gardent la liste d'un seul tenant."),
                Fonctionnalite(symbole: "person.2.fill", titre: "Vu avec qui ?",
                               detail: "Un film terminé, un épisode regardé, une série finie : Séance demande qui l'a vu avec toi, en cochant d'office les personnes de « Qui regarde ce soir ? ». Le titre s'inscrit directement chez elles — dans leurs Terminés, hors de leur « À voir » — et leur sous-dossier se synchronise aussitôt, pour qu'elles le retrouvent sur leurs appareils."),
                Fonctionnalite(symbole: "appletv", titre: "Apple TV : changer de personne",
                               detail: "Le prénom en haut à gauche est un bouton : depuis le menu du haut, vers la gauche, la télécommande l'atteint et rouvre « Qui regarde ? », comme sur l'iPad."),
                Fonctionnalite(symbole: "tv", titre: "« W9 », plus « W9.fr »",
                               detail: "Une chaîne du guide pas encore connue par son nom s'affichait avec son identifiant technique ; elle prend le nom du catalogue."),
            ]
        ),
        NoteVersion(
            numero: "6.0.2",
            date: "21 septembre 2026",
            resume: "Tu vois qui regarde, en haut à gauche de chaque page ; « Aujourd'hui » passe aux grandes cartes ; la fiche de présentation parle de la version 6.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.crop.circle", titre: "Qui regarde, toujours affiché",
                               detail: "Dès que la maison a plusieurs profils, le prénom de la personne en cours s'affiche en haut à gauche de chaque page, à la hauteur du menu, avec son symbole. Un toucher ouvre « Qui regarde ? » pour changer. Sur le Mac, il est aussi dans le titre de la fenêtre ; sur l'Apple TV, à gauche du menu du haut."),
                Fonctionnalite(symbole: "calendar", titre: "« Aujourd'hui » en grandes cartes",
                               detail: "Les rendez-vous du jour de l'accueil passent de la liste serrée aux cartes 16/9 du reste de l'app : l'image, ce qui se passe en orange (« Sur W9 à 18:22 », « Nouvel épisode S02E04 »), le titre. Une ligne résume la journée ; « Tout voir » ouvre toujours À venir."),
                Fonctionnalite(symbole: "envelope.fill", titre: "La carte E-mail à la bonne hauteur",
                               detail: "Dans Réglages, elle annonçait le nombre de destinataires sur une ligne de plus et dépassait ses voisines. Elle dit maintenant « Activé » ou « À terminer », comme les autres."),
                Fonctionnalite(symbole: "person.2.fill", titre: "Le profil principal garde son nom",
                               detail: "Sans prénom enregistré, il prenait celui de la personne en cours : quand Anne regardait, « Qui regarde ? » montrait deux « Anne », et le premier menait au profil principal. Il s'appelle maintenant « Moi » tant qu'un autre profil est ouvert."),
                Fonctionnalite(symbole: "tv", titre: "« TV » aussi dans À venir",
                               detail: "Les cartes des passages à la TV portaient encore l'étiquette « TÉLÉ »."),
                Fonctionnalite(symbole: "lock.shield", titre: "Les essais sur le Mac ne touchent plus à tes données",
                               detail: "La démonstration qui sert aux captures partage l'identifiant de la vraie app : sur le Mac, elle ne synchronise plus, n'envoie plus l'e-mail de la semaine, ne démarre plus la centrale et ne remplace plus tes alertes ni ton index Spotlight."),
                Fonctionnalite(symbole: "doc.richtext", titre: "Fiche de présentation : version 6",
                               detail: "Douze pages et de nouvelles captures en cartes 16/9 : une page pour la Famille, « Qui regarde ? » sur l'Apple TV, l'e-mail de la semaine, la centrale de la maison et Spotlight."),
            ]
        ),
        NoteVersion(
            numero: "6.0.1",
            date: "21 septembre 2026",
            resume: "La famille voyage entre tes appareils et se choisit sur l'Apple TV ; le Mac retrouve des pages homogènes et un accès aux Réglages qui marche partout.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.2.fill", titre: "La famille arrive sur tous tes appareils",
                               detail: "Les personnes créées dans Réglages › Famille voyagent avec la synchronisation : l'iPad, le Mac et l'Apple TV les reçoivent, avec le même identifiant, et chacune retrouve ses listes dans son sous-dossier. Rien n'est jamais retiré à distance : supprimer un profil reste un geste local."),
                Fonctionnalite(symbole: "appletv", titre: "Apple TV : « Qui regarde ? »",
                               detail: "À l'ouverture dès que la maison a plusieurs profils, et dans Réglages › Famille pour changer en cours de route. Chaque personne a son magasin sur la TV et se synchronise dans son sous-dossier du NAS ; la bibliothèque du NAS et le guide TV restent communs."),
                Fonctionnalite(symbole: "menubar.rectangle", titre: "Mac : « Réglages » dans le menu",
                               detail: "La roue dentée posée par-dessus les pages tombait sous le menu, recouvrait la recherche d'Explorer et le bouton de l'accueil, et ne répondait pas sur Préférences. Les Réglages sont maintenant une entrée du menu du haut, à sa hauteur, qui marche sur toutes les pages (la barre du Mac n'affiche que du texte : pas d'icône possible)."),
                Fonctionnalite(symbole: "rectangle.grid.2x2", titre: "Mac et iPad : le même format partout",
                               detail: "Une seule grille pour toutes les pages en cartes 16/9, calée sur la taille des étagères : « Tout voir », le NAS et les listes nommées serraient leurs cartes dans des colonnes d'affiches, d'autres pages les laissaient grossir jusqu'à 520 points. Les listes nommées, dernière page en affiches verticales, passent aux grandes cartes."),
                Fonctionnalite(symbole: "arrow.left.and.right", titre: "Mac : Préférences sur toute la largeur",
                               detail: "La page s'arrêtait à 1180 points et laissait deux bandes vides dans une grande fenêtre."),
            ]
        ),
        NoteVersion(
            numero: "6.0",
            date: "21 septembre 2026",
            resume: "La famille : un profil par personne. Et un Mac qui veille sur la maison, l'Apple TV enfin testée à la télécommande, tes titres dans Spotlight.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.2.fill", titre: "Famille : un profil par personne",
                               detail: "Réglages › Famille : chacun a ses listes, ses notes, ses pouces, ses soirées et ses idées du soir. Les plateformes, les chaînes, le NAS et les clés restent ceux de la maison et suivent d'un profil à l'autre. « Qui regarde ? » à l'ouverture, comme sur Netflix ; ton profil de toujours ne change pas, rien n'est migré."),
                Fonctionnalite(symbole: "person.3.fill", titre: "Qui regarde ce soir ?",
                               detail: "Dans « Ce soir », coche qui regarde avec toi : Séance fond vos goûts et cherche ce qui plaît à tous. Un genre que l'un de vous déteste est évité plutôt que moyenné, et rien de ce que l'un a vu ou écarté n'est proposé."),
                Fonctionnalite(symbole: "arrow.triangle.2.circlepath", titre: "Chaque profil se synchronise",
                               detail: "Dans un sous-dossier « Famille/Prénom » du dossier d'iCloud Drive et du NAS : crée un profil du même prénom sur un autre appareil, ils se retrouvent. Le widget suit le profil en cours. L'Apple TV et l'e-mail de la semaine suivent le profil principal."),
                Fonctionnalite(symbole: "house.and.flag.fill", titre: "Mac : la centrale de la maison",
                               detail: "Séance n'a pas de serveur : sans app ouverte, rien n'avance. Sur un Mac qui reste allumé (Réglages › Centrale de la maison), elle passe tous les quarts d'heure : elle synchronise l'iCloud Drive et le NAS — le pont entre l'Apple TV et tes autres appareils —, relit le guide TV et le NAS, recalcule les alertes et envoie l'e-mail de la semaine à l'heure dite. Elle peut s'ouvrir à l'ouverture de session, et garde le Mac éveillé."),
                Fonctionnalite(symbole: "appletv", titre: "Apple TV : un acteur s'ouvre aussi depuis l'accueil",
                               detail: "Depuis une fiche ouverte de l'accueil ou de l'étagère du haut, choisir un visage du casting ne faisait rien : le chemin de navigation n'acceptait que des titres. Trouvé par les nouveaux tests de la TV, qui rejouent tes gestes à la télécommande : le menu, la fiche jusqu'au casting et à l'acteur, les réglages."),
                Fonctionnalite(symbole: "magnifyingglass", titre: "Tes titres dans Spotlight",
                               detail: "Tape le nom d'un titre de tes listes dans la recherche de l'iPhone, de l'iPad ou du Mac : sa fiche s'ouvre dans Séance. L'index reste sur l'appareil."),
                Fonctionnalite(symbole: "play.tv", titre: "La plateforme qui s'ouvre vraiment",
                               detail: "Séance retient quelles plateformes acceptent d'être ouvertes sur un titre : « Regarder maintenant » les préfère, et une plateforme qui refuse le dit tout de suite au lieu de ne rien faire."),
            ]
        ),
        NoteVersion(
            numero: "5.4",
            date: "21 septembre 2026",
            resume: "Un dossier supprimé sur le NAS ne bloque plus l'analyse, et le menu de ton NAS ne garde que les rayons qui ont quelque chose.",
            fonctionnalites: [
                Fonctionnalite(symbole: "folder.badge.minus", titre: "Un dossier supprimé n'arrête plus tout",
                               detail: "Un dossier déclaré dans les réglages mais effacé du NAS faisait échouer l'analyse entière : la bibliothèque restait figée sur ce qu'elle savait avant. Il est maintenant laissé de côté, et les autres dossiers sont relus normalement. Si plus aucun dossier ne répond, Séance le dit toujours, et le bouton « Tester » des réglages nomme le dossier manquant."),
                Fonctionnalite(symbole: "rectangle.3.group", titre: "Le menu de ton NAS suit ce qui reste",
                               detail: "Films, Séries, NEW, Non reconnus : les rayons vides quittent le menu du haut dès l'analyse suivante, au lieu d'y laisser une case qui ne mène à rien."),
                Fonctionnalite(symbole: "questionmark.folder", titre: "« Autres » devient « Non reconnus »",
                               detail: "Le rayon dit ce qu'il contient : les fichiers dont Séance n'a pas trouvé la fiche TMDB."),
            ]
        ),
        NoteVersion(
            numero: "5.3",
            date: "21 septembre 2026",
            resume: "Un seul format partout : la grande carte de « Ce soir à la TV », avec l'heure, la durée et la source, sur toutes les pages et tous tes appareils.",
            fonctionnalites: [
                Fonctionnalite(symbole: "rectangle.on.rectangle", titre: "La même carte, partout",
                               detail: "Mes listes, Explorer, le programme TV, ton NAS, les documentaires, tes favoris, la filmographie d'un acteur et les propositions de soirée passent au format 16/9 de « Ce soir à la TV » : l'image en grand, où regarder en haut à gauche, puis la ligne orange — la chaîne et l'heure, « Sur ton NAS · 4K », la plateforme —, le titre, le type, l'année, la durée et la note."),
                Fonctionnalite(symbole: "appletv", titre: "L'Apple TV suit",
                               detail: "Ce soir, Mes listes, Explorer, le NAS, les Préférences et la filmographie montrent la même grande carte, trois par rangée. Les affiches verticales ne servent plus qu'aux portraits d'acteurs."),
                Fonctionnalite(symbole: "gearshape.fill", titre: "Mac : la roue dentée répond",
                               detail: "Elle était posée dans la bande que macOS réserve à la barre de titre, où le clic ne l'atteignait jamais. Elle descend de quelques points. Au clavier, ⌘, ouvre toujours les Réglages."),
                Fonctionnalite(symbole: "macwindow", titre: "Mac : « Ce soir » occupe la fenêtre",
                               detail: "La page s'arrêtait à 1180 points de large, là où les autres s'étalent : sur un grand écran, elle laissait deux bandes vides."),
                Fonctionnalite(symbole: "film", titre: "Une vidéo .avi ou .mkv part dans VLC",
                               detail: "Séance lit le MP4, le MOV et le M4V ; les autres formats s'ouvraient dans son lecteur pour n'afficher qu'un message. Ils vont maintenant directement dans VLC, et l'alerte propose le bouton qui l'ouvre."),
                Fonctionnalite(symbole: "photo", titre: "La bonne image, pas une affiche rognée",
                               detail: "Chaque page demande maintenant l'image large de ses titres : sans elle, la carte aurait coupé l'affiche en deux. La ligne orange, elle, se limite à deux sources pour ne plus être tronquée."),
            ]
        ),
        NoteVersion(
            numero: "5.2",
            date: "20 septembre 2026",
            resume: "Les documentaires arrivent, tes favoris se partagent, tes vidéos de famille se lisent dans l'app — et Séance s'ouvre et défile plus vite.",
            fonctionnalites: [
                Fonctionnalite(symbole: "film.stack", titre: "Les documentaires, troisième catégorie",
                               detail: "Une page Documentaires et une étagère sur l'accueil, avec dix thèmes à cocher — animaux et nature, sciences et espace, histoire, société et enquêtes, sport, musique, voyages, cuisine, art, technologie. TMDB n'a pas de sous-genres de documentaires : chaque thème est un jeu de mots-clés, cherchés une fois puis gardés. Ils ont leurs propres suggestions et ne viennent pas se mêler aux idées du soir."),
                Fonctionnalite(symbole: "star.fill", titre: "Tes favoris, à partager",
                               detail: "Une collection à part, ni « À voir » ni « J'aime » : tes incontournables, vus ou non. Depuis une fiche (« Plus ») ou un appui long sur une affiche ; l'onglet Favoris de Mes listes les montre en grille, et « Partager ma liste » l'envoie par Messages, Mail ou AirDrop. Ils voyagent dans la sauvegarde et la synchronisation, suppressions comprises."),
                Fonctionnalite(symbole: "calendar.badge.clock", titre: "« À venir » sur l'Apple TV",
                               detail: "Mes listes gagne son onglet « À venir » sur la télévision : sorties, nouveaux épisodes et passages à la télé de tes titres, calculés sur la TV même — elle n'a pas de notifications, mais elle sait dire ce qui arrive."),
                Fonctionnalite(symbole: "bolt", titre: "Des recherches indexées",
                               detail: "Chaque affiche demande au magasin « ce titre est-il sur le NAS ? », et la grille télé lui demande une tranche d'horaire. Ces questions passaient en revue toute la vidéothèque et tout le guide ; elles ont maintenant leur index. Ta base est reprise telle quelle, sans rien perdre."),
                Fonctionnalite(symbole: "square.stack.3d.down.right", titre: "L'accueil lit moins",
                               detail: "Il relisait tout le guide télé, toutes tes listes et toutes tes échéances pour n'en montrer que quelques lignes. Il ne demande plus que le jour en cours et la quarantaine de titres affichés."),
                Fonctionnalite(symbole: "photo.stack", titre: "Les grandes images arrivent en avance",
                               detail: "Les cartes 16/9 de l'accueil se chargent pendant que tu lis le haut de l'écran : au défilement, l'image est déjà là plutôt qu'un rectangle gris."),
                Fonctionnalite(symbole: "lightbulb", titre: "Tes idées du soir, déjà prêtes",
                               detail: "Les dernières idées sont gardées sur l'appareil : au lancement suivant, elles s'affichent tout de suite au lieu d'une roue. Elles se recalculent d'elles-mêmes au bout de six heures, le lendemain, ou dès que tes plateformes, tes listes ou tes « J'aime » changent."),
                Fonctionnalite(symbole: "externaldrive.connected.to.line.below", titre: "Une seule connexion au NAS",
                               detail: "La synchronisation ouvrait une connexion SMB par fichier lu ou écrit — sonde du réseau, ouverture du partage, fermeture, à chaque fois. Un passage tient maintenant dans une seule connexion, et le dossier n'est listé qu'une fois."),
                Fonctionnalite(symbole: "play.circle.fill", titre: "« Regarder maintenant », un seul bouton",
                               detail: "Sur la carte d'une soirée, plus de pastilles à comparer : un bouton, et Séance choisit — ton NAS d'abord, sinon une plateforme de tes abonnements, sinon la chaîne qui le passe. Les autres accès restent écrits dessous."),
                Fonctionnalite(symbole: "eye", titre: "« Déjà vu » sur une idée",
                               detail: "Une idée que tu as déjà vue se range d'un toucher : elle sort des propositions et nourrit tes goûts, sans entrer dans tes statistiques."),
                Fonctionnalite(symbole: "play.rectangle.on.rectangle", titre: "Tes vidéos de famille se lisent dans Séance",
                               detail: "Plus besoin d'Infuse ni de VLC : la vidéo reste sur le NAS et se lit ici même, par morceaux, avec les commandes d'iOS. C'est ce qui ne démarrait pas toujours sur l'iPhone. Formats lus : MP4, MOV, M4V — ce que filme un iPhone ; pour un MKV, Séance renvoie vers VLC. Réglages › Vidéos personnelles › « Lire dans Séance » permet de revenir à l'ancienne façon."),
                Fonctionnalite(symbole: "moon.zzz", titre: "Après minuit, la soirée reste la bonne",
                               detail: "Entre minuit et six heures, « Ce soir » montre la soirée commencée la veille — mais « Ajouter à ma soirée » proposait déjà le lendemain : les titres ajoutés disparaissaient de l'écran. La feuille part maintenant de la soirée en cours."),
                Fonctionnalite(symbole: "arrow.uturn.backward", titre: "Annuler, partout",
                               detail: "« Ajouté à À voir », « Marqué vu », « Ajouté à ma soirée », « Remis dans Terminés », depuis une affiche comme depuis une fiche : chaque message propose « Annuler » pendant cinq secondes. « Je n'aime pas » et « Regardé » de la soirée aussi."),
            ]
        ),
        NoteVersion(
            numero: "5.1",
            date: "20 septembre 2026",
            resume: "Un accueil en grandes cartes, « Aujourd'hui » d'un coup d'œil, et un essai d'alerte fait pour l'Apple Watch.",
            fonctionnalites: [
                Fonctionnalite(symbole: "rectangle.fill", titre: "Partout, la grande carte de « Ce soir à la TV »",
                               detail: "Regardable ce soir, le Top de l'année, Du moment et ton NAS passent au même format 16/9 : l'image en grand, où regarder en haut à gauche, et dessous ce qui compte — « Sur ton NAS · 4K », la plateforme, le rang, l'année, la durée, la note."),
                Fonctionnalite(symbole: "calendar", titre: "Aujourd'hui, sur l'accueil",
                               detail: "Ce qui sort ou passe aujourd'hui pour tes titres, en quelques lignes ; « Tout voir » ouvre Mes listes › À venir."),
                Fonctionnalite(symbole: "calendar.badge.minus", titre: "À venir, un jour à la fois",
                               detail: "Le bouton « Tout » disparaît : une série qui passe chaque soir à la TV s'y répétait autant de fois, et noyait le reste. La page s'ouvre sur le jour le plus proche."),
                Fonctionnalite(symbole: "applewatch", titre: "Tester une alerte sur l'Apple Watch",
                               detail: "iOS ne transmet une alerte à la montre que si l'iPhone est verrouillé : un essai immédiat, téléphone en main, n'y arrive jamais. Réglages › Alertes a maintenant un essai à vingt secondes, avec la consigne de verrouiller, et signale ce qui bloque dans les réglages de notification de Séance. L'essai demandé depuis l'Apple TV attend lui aussi vingt secondes."),
                Fonctionnalite(symbole: "envelope.arrow.triangle.branch", titre: "L'e-mail de la semaine voyage entre tes appareils",
                               detail: "Destinataires, jour, heure et compte d'envoi passent par la synchronisation et la sauvegarde, avec la date du dernier envoi pour éviter les doublons. Le mot de passe, lui, reste dans le trousseau de chaque appareil."),
                Fonctionnalite(symbole: "minus.circle", titre: "Accueil allégé",
                               detail: "Le rappel « Sur 7 plateformes seulement · Modifier » est retiré ; le réglage reste dans la feuille de l'accueil."),
            ]
        ),
        NoteVersion(
            numero: "5.0",
            date: "20 septembre 2026",
            resume: "L'e-mail de la semaine, des suggestions sur la page Ce soir, des Réglages en grandes cartes, et « Préférences ».",
            fonctionnalites: [
                Fonctionnalite(symbole: "envelope.fill", titre: "L'e-mail de la semaine",
                               detail: "Une fois par semaine, au jour et à l'heure que tu choisis : les épisodes, sorties et passages à la TV de tes titres, les nouveautés de tes plateformes et tes soirées prévues, mis en page aux couleurs de Séance. Plusieurs destinataires, séparés par un point-virgule ; un bouton d'essai et un aperçu. Il part de ton appareil, par ton compte de messagerie (port 465) : Séance n'a pas de serveur."),
                Fonctionnalite(symbole: "sparkles", titre: "Suggestions pour toi, sur la page Ce soir",
                               detail: "À côté de « Surprends-moi » : une rangée de titres regardables sur tes plateformes, choisis d'abord d'après les acteurs que tu suis, puis tes pouces levés et tes notes. « + » les ajoute à la soirée."),
                Fonctionnalite(symbole: "person.2.fill", titre: "Une nouvelle série d'un acteur suivi",
                               detail: "Les nouveaux films d'un acteur suivi étaient déjà annoncés ; ses nouvelles séries le sont aussi."),
                Fonctionnalite(symbole: "rectangle.grid.1x2.fill", titre: "Des Réglages en grandes cartes",
                               detail: "En tête, où en est Séance et le geste du moment — ce qui reste à régler, ou « Synchroniser » ; dessous, une grande carte par réglage, dans le dessin des cartes de « Ce soir », avec les symboles de l'app. La même page sur l'iPhone, l'iPad, le Mac et l'Apple TV."),
                Fonctionnalite(symbole: "gearshape.fill", titre: "Mac : la roue dentée en haut à droite",
                               detail: "Les Réglages quittent le menu du Mac : une roue dentée les ouvre depuis toutes les pages, comme sur l'Apple TV."),
                Fonctionnalite(symbole: "slider.horizontal.3", titre: "« Préférences » au lieu de « Profil »",
                               detail: "La page dit mieux ce qu'elle contient : tes goûts, tes acteurs, tes notes."),
            ]
        ),
        NoteVersion(
            numero: "4.9",
            date: "20 septembre 2026",
            resume: "Le menu en haut sur le Mac, un bouton pour synchroniser tes appareils, et des Réglages plus directs.",
            fonctionnalites: [
                Fonctionnalite(symbole: "menubar.rectangle", titre: "Mac : le menu en haut",
                               detail: "Comme sur l'iPad et l'Apple TV : les onglets en haut de la fenêtre, plus de barre latérale. ⌘1 à ⌘6 changent toujours d'onglet."),
                Fonctionnalite(symbole: "arrow.triangle.2.circlepath", titre: "Synchroniser mes appareils maintenant",
                               detail: "Un bouton en tête des Réglages : listes, soirées, notes, pouces, plateformes, chaînes et réglages passent par ton dossier d'iCloud Drive (et par le NAS s'il est activé). Sans dossier choisi, il t'y mène."),
                Fonctionnalite(symbole: "bell.badge", titre: "L'essai d'alerte depuis l'Apple TV arrive enfin",
                               detail: "La TV déposait bien sa demande sur le NAS, mais l'iPhone ne lisait pas ce dossier : « Par le NAS » n'y était pas activé. Il l'est maintenant d'office dès que le NAS est réglé — ce qui fait aussi arriver tes listes sur la TV. Réglages › Alertes gagne « Tester sur mes autres appareils », depuis l'iPad, le Mac ou l'iPhone."),
                Fonctionnalite(symbole: "square.grid.2x2", titre: "Séance, Versions, Journal : trois tuiles",
                               detail: "La page « À propos » et ses onglets laissent place à trois tuiles dans les Réglages, à côté de Claude : ce que fait Séance, ce qui a changé, ce qui s'est passé."),
            ]
        ),
        NoteVersion(
            numero: "4.8.2",
            date: "20 septembre 2026",
            resume: "Apple TV : les acteurs se choisissent partout, une image de fond sur les pages, les réglages en roue dentée.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.2", titre: "Apple TV : le casting enfin à portée",
                               detail: "Sur la fiche d'un film du NAS ou de la TV, la télécommande ne descendait pas jusqu'aux acteurs : la section « Où regarder », sans rien à choisir, l'arrêtait. On descend maintenant jusqu'au casting, et chaque visage ouvre sa fiche, où on peut le suivre."),
                Fonctionnalite(symbole: "photo", titre: "Apple TV : une image de fond",
                               detail: "Derrière chaque page, une grande image d'un de tes titres, floutée et fondue dans le noir ; elle change chaque jour."),
                Fonctionnalite(symbole: "gearshape", titre: "Apple TV : les réglages en roue dentée",
                               detail: "Tout à droite du menu, une icône au lieu d'un mot : le menu est plus court, et les réglages se trouvent d'un coup d'œil."),
                Fonctionnalite(symbole: "bell.badge", titre: "Tester une alerte depuis l'Apple TV",
                               detail: "L'Apple TV n'affiche pas de notification. Réglages de la TV › « Tester une alerte » dépose une demande sur le NAS : ton iPhone la découvre à sa prochaine synchronisation et prévient, l'Apple Watch avec lui. Sur l'iPhone, l'essai de Réglages › Alertes se voit sur la montre quand l'iPhone est verrouillé."),
            ]
        ),
        NoteVersion(
            numero: "4.8.1",
            date: "20 septembre 2026",
            resume: "Sur le Mac, « Lire » lance vraiment le film ; et « Télé » s'appelle maintenant « TV ».",
            fonctionnalites: [
                Fonctionnalite(symbole: "macbook", titre: "Mac : le film démarre",
                               detail: "Le Mac demandait au Finder de monter le partage du NAS, ce qui n'ouvrait pas toujours le film. Si Infuse est installé, le titre s'ouvre maintenant dans sa bibliothèque et démarre aussitôt, comme sur l'iPhone et l'Apple TV."),
                Fonctionnalite(symbole: "play.fill", titre: "« Lire sur le NAS » en tête de fiche",
                               detail: "La pastille « Sur ton NAS » du haut de la fiche n'était qu'une étiquette : on la touchait pour rien. Elle lance maintenant le film, ou le prochain épisode de la série ; les plateformes s'ouvrent sur le titre, la TV mène au programme."),
                Fonctionnalite(symbole: "tv", titre: "« TV » au lieu de « Télé »",
                               detail: "Partout dans l'app : l'onglet, la source d'Explorer, « Ce soir à la TV », « Programme TV »."),
            ]
        ),
        NoteVersion(
            numero: "4.8",
            date: "20 septembre 2026",
            resume: "L'Apple TV rattrape l'iPhone : fiche complète, fiche des acteurs, épisodes, pouces, note, idées du soir.",
            fonctionnalites: [
                Fonctionnalite(symbole: "person.2", titre: "Apple TV : le casting et la fiche des acteurs",
                               detail: "Chaque visage du casting ouvre la fiche de la personne : portrait, biographie, « 12 films vus sur 38 », ses films et ses séries en étagères, et « Suivre ». Tes acteurs du Profil s'ouvrent de même."),
                Fonctionnalite(symbole: "list.number", titre: "Apple TV : tous les épisodes",
                               detail: "Saison par saison, avec le prochain à regarder. Choisir une ligne coche l'épisode ; « Lire » est à côté quand il est sur le NAS."),
                Fonctionnalite(symbole: "play.tv", titre: "Apple TV : où regarder, en détail",
                               detail: "Le NAS, tes plateformes — chacune s'ouvre sur le titre —, et les passages télé avec la chaîne, le jour et l'heure ; sinon, où louer ou acheter."),
                Fonctionnalite(symbole: "hand.thumbsup", titre: "Apple TV : pouces, note, alertes, un autre soir",
                               detail: "« J'aime » et « Je n'aime pas » sans avoir vu, la note de 1 à 10 après, la cloche (c'est l'iPhone qui prévient), « Un autre soir… » avec ses sept tuiles de jours, et les bandes-annonces dans l'app YouTube."),
                Fonctionnalite(symbole: "sparkles", titre: "Apple TV : des idées pour ce soir",
                               detail: "Sous ta soirée, des titres regardables sur tes plateformes, classés selon tes goûts ; le Profil montre aussi tes pouces levés."),
                Fonctionnalite(symbole: "macbook", titre: "Mac : tes vidéos personnelles dans Infuse",
                               detail: "Le Mac faisait monter le partage par le Finder puis ouvrait le lecteur de macOS, d'où l'attente. Si Infuse est installé et choisi dans Réglages › Lecture, la vidéo lui est passée directement, comme sur l'Apple TV."),
            ]
        ),
        NoteVersion(
            numero: "4.7",
            date: "20 septembre 2026",
            resume: "Les pouces, comme sur Netflix : dis ce qui te plaît sans l'avoir vu, et les idées du soir te ressemblent davantage.",
            fonctionnalites: [
                Fonctionnalite(symbole: "hand.thumbsup", titre: "J'aime",
                               detail: "Un pouce levé sur la fiche, sur une idée du soir ou par appui long sur une affiche. Pas besoin d'avoir vu le titre, et il n'entre dans aucune liste : Séance en retient les genres et les acteurs pour tes prochaines idées. La note de 1 à 10 reste pour après avoir regardé."),
                Fonctionnalite(symbole: "hand.thumbsdown", titre: "Je n'aime pas, à côté",
                               detail: "Le pouce baissé est maintenant visible sur la fiche, plus dans le menu « Plus ». Le titre ne t'est plus proposé, et Séance apprend enfin de ce refus : elle en retient les genres, ce qu'elle ne faisait pas. Un pouce chasse l'autre."),
                Fonctionnalite(symbole: "list.bullet", titre: "Tes pouces dans les Réglages",
                               detail: "Réglages › Prénom et idées liste les titres que tu aimes et ceux que tu as écartés, pour retirer un pouce ou tout reproposer. Ils voyagent dans la sauvegarde et la synchronisation."),
                Fonctionnalite(symbole: "arrow.left.and.right", titre: "Fiches recadrées sur l'iPhone",
                               detail: "Depuis la 4.5, la rangée d'actions d'un film comptait six boutons : trop pour l'iPhone, toute la fiche s'élargissait et se retrouvait rognée à gauche. La bande-annonce n'entre plus dans la rangée que sur l'iPad et le Mac ; sur l'iPhone elle garde sa section, plus bas."),
            ]
        ),
        NoteVersion(
            numero: "4.6",
            date: "20 septembre 2026",
            resume: "Tes listes arrivent sur l'Apple TV, toutes seules : la synchronisation passe aussi par le NAS.",
            fonctionnalites: [
                Fonctionnalite(symbole: "externaldrive.connected.to.line.below", titre: "Synchroniser par le NAS",
                               detail: "Réglages › Sauvegarde › « Par le NAS » : Séance dépose son fichier dans un dossier « Séance » du NAS et y lit ceux des autres, en plus du dossier d'iCloud Drive. À la maison seulement ; ailleurs rien ne se perd, tout se rattrape au retour. Le compte du NAS doit pouvoir écrire dans le partage."),
                Fonctionnalite(symbole: "appletv", titre: "L'Apple TV reçoit tes listes",
                               detail: "À voir, en cours, soirées prévues, plateformes, chaînes et goûts arrivent sur la TV au lancement et à chaque retour dans l'app ; ce que tu fais sur la TV — garder un titre, marquer un film vu — revient sur l'iPhone. Suppressions et retours en arrière compris, le plus récent l'emportant."),
                Fonctionnalite(symbole: "iphone.and.arrow.forward", titre: "Activée après l'envoi par code",
                               detail: "Quand l'iPhone configure une TV par son code à six chiffres, « Par le NAS » s'active dans la foulée : plus besoin de renvoyer un code pour mettre la TV à jour. Réglages de la TV › « Synchronisation avec tes appareils » dit quand le dernier passage a eu lieu, et le relance."),
            ]
        ),
        NoteVersion(
            numero: "4.5",
            date: "20 septembre 2026",
            resume: "Ta soirée en quelques touchers : où regarder chaque titre tout de suite, l'épisode 1 d'une série jamais commencée, et « Je n'aime pas ».",
            fonctionnalites: [
                Fonctionnalite(symbole: "play.tv", titre: "Où regarder, tout de suite",
                               detail: "Sur chaque titre de ta soirée, sur les idées et dans la recherche : « Lire sur le NAS » lance la vidéo, « Netflix », « Prime Video » ou « Apple TV » ouvrent la plateforme sur le titre, et la télé donne la chaîne, le jour et l'heure. Seules tes plateformes cochées comptent ; sinon Séance dit « Dans aucun de tes abonnements »."),
                Fonctionnalite(symbole: "1.circle", titre: "Le premier épisode d'une série",
                               detail: "Une série jamais commencée, ajoutée à ta soirée, disait « Aucun nouvel épisode disponible ». Elle propose maintenant « S01E01 · son titre », avec sa durée et le bouton « Regardé »."),
                Fonctionnalite(symbole: "moon.stars", titre: "Un épisode, pas toute la série",
                               detail: "L'épisode regardé, la série quitte ta soirée — depuis « Ce soir » comme depuis sa fiche. « Encore un » la remet pour enchaîner. La durée de la soirée compte le film et un épisode par série."),
                Fonctionnalite(symbole: "magnifyingglass", titre: "Chercher sans quitter la soirée",
                               detail: "« Ajouter à ma soirée » a son champ de recherche : films et séries mêlés, où les regarder, et « + » sur chaque ligne. Au-dessus des idées, tu choisis films, séries ou les deux."),
                Fonctionnalite(symbole: "moon.fill", titre: "La lune sur la fiche",
                               detail: "« Ce soir » a son bouton dans la rangée d'actions de la fiche, plus derrière « Plus », et un message confirme l'ajout, avec Annuler."),
                Fonctionnalite(symbole: "hand.thumbsdown", titre: "Je n'aime pas",
                               detail: "Sur une idée, une affiche (appui long) ou une fiche : le titre ne t'est plus proposé, ni dans les idées, ni sur l'accueil, ni dans Explorer. Un film que tu viens de regarder ne revient plus non plus dans les idées. Réglages › Prénom et idées liste ce que tu as écarté et permet de tout reproposer."),
                Fonctionnalite(symbole: "appletv", titre: "Apple TV : le menu en haut",
                               detail: "Le menu passe en haut de l'écran, à l'horizontale, comme Netflix. Et une ligne sélectionnée (tes vidéos personnelles, les réglages) garde son texte lisible : il passait au blanc sur blanc."),
            ]
        ),
        NoteVersion(
            numero: "4.4.1",
            date: "20 septembre 2026",
            resume: "Tes vidéos personnelles s'ouvrent dans le lecteur que tu as choisi, Infuse compris.",
            fonctionnalites: [
                Fonctionnalite(symbole: "play.rectangle", titre: "Vidéos personnelles : ton lecteur",
                               detail: "Elles passaient d'office par VLC. Elles s'ouvrent maintenant dans le lecteur de Réglages › Lecture. N'ayant pas de fiche TMDB, elles ne peuvent pas s'ouvrir dans la bibliothèque d'Infuse comme un film du NAS : Séance lui passe le fichier à son adresse. Si rien ne se lance, l'écran te propose de choisir VLC."),
            ]
        ),
        NoteVersion(
            numero: "4.4",
            date: "20 septembre 2026",
            resume: "L'Apple TV refaite : une grande image d'accueil, des réglages enfin lisibles, et les écrans de l'iPhone.",
            fonctionnalites: [
                Fonctionnalite(symbole: "rectangle.on.rectangle", titre: "Apple TV : l'accueil en grand",
                               detail: "Ta soirée s'affiche en pleine largeur, titre et boutons posés dessus, les étagères en dessous — comme les apps de télévision."),
                Fonctionnalite(symbole: "eye", titre: "Apple TV : des réglages lisibles",
                               detail: "Les pages de réglage étaient transparentes : le texte de la page précédente se lisait au travers, et un libellé pouvait tourner au blanc sur blanc. Elles sont refaites avec les composants de Séance, chaque couleur maîtrisée."),
                Fonctionnalite(symbole: "square.grid.2x2", titre: "Apple TV : les écrans de l'iPhone",
                               detail: "« Ce soir » a sa rangée de jours, « Mes listes » ses onglets À voir, En cours, Terminés et Listes, et les réglages se modifient tous à la télécommande."),
            ]
        ),
        NoteVersion(
            numero: "4.3",
            date: "20 septembre 2026",
            resume: "Où regarder chaque titre d'un coup d'œil, tes vidéos personnelles sur le NAS, et une app d'un seul style.",
            fonctionnalites: [
                Fonctionnalite(symbole: "rectangle.stack.badge.play", titre: "Où regarder, sur l'affiche et sur la fiche",
                               detail: "Une affiche porte maintenant toutes ses sources à la fois : ton NAS, les logos de tes plateformes, et la télé avec la chaîne et l'heure du prochain passage. En tête de fiche, la même chose en toutes lettres."),
                Fonctionnalite(symbole: "video.fill", titre: "Tes vidéos personnelles",
                               detail: "Réglages › Vidéos personnelles : coche l'option, et Séance lit un second partage de ton NAS — un autre serveur si tu veux. Tes films de famille se parcourent par dossier, sur tous tes appareils. Ils restent privés : leurs noms ne partent vers aucun service, et ils n'entrent ni dans tes statistiques ni dans tes goûts."),
                Fonctionnalite(symbole: "square.grid.2x2", titre: "Un seul style",
                               detail: "Les cases d'Explorer servent partout : Mes listes, le NAS, le programme télé, la page d'un acteur. « Du moment » s'appelle « Nouveautés ». La charte graphique de l'app est écrite dans Documentation."),
                Fonctionnalite(symbole: "appletv.fill", titre: "Apple TV : on ressort de chaque page",
                               detail: "La touche Retour refermait l'app depuis « À propos » : chaque page la traite maintenant elle-même."),
            ]
        ),
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

import Foundation

/// Une icône de souvenir (6.2) : un SF Symbol de la charte, son nom, et les mots qui la font proposer.
public struct IconeSouvenir: Sendable, Hashable, Identifiable {
    public let symbole: String
    public let libelle: String
    let motsCles: [String]

    public var id: String { symbole }
}

/// Les vingt-quatre icônes de la feuille « Couverture », dans l'ordre de la maquette validée par Patrick (piste B,
/// 22 septembre 2026), et la suggestion d'après un nom : « Anniversaire de Camille » → gâteau, « Ski à Verbier » → skieur.
public enum IconesSouvenirs {
    public static let toutes: [IconeSouvenir] = [
        IconeSouvenir(symbole: "stroller.fill", libelle: "Naissance", motsCles: ["naissance", "maternite", "accouchement", "premiers pas"]),
        IconeSouvenir(symbole: "teddybear.fill", libelle: "Bébé", motsCles: ["bebe", "baby", "bapteme"]),
        IconeSouvenir(symbole: "heart.fill", libelle: "Mariage", motsCles: ["mariage", "noces", "wedding", "fiancailles"]),
        IconeSouvenir(symbole: "birthday.cake.fill", libelle: "Anniversaire", motsCles: ["anniversaire", "anniv", "birthday"]),
        IconeSouvenir(symbole: "gift.fill", libelle: "Cadeaux", motsCles: ["cadeau"]),
        IconeSouvenir(symbole: "party.popper.fill", libelle: "Fête", motsCles: ["fete", "soiree", "carnaval", "nouvel an", "reveillon"]),
        IconeSouvenir(symbole: "beach.umbrella.fill", libelle: "Vacances", motsCles: ["vacances", "plage", "mer ", "ete ", "piscine"]),
        IconeSouvenir(symbole: "airplane", libelle: "Voyage", motsCles: ["voyage", "avion", "trip", "sejour", "visite"]),
        IconeSouvenir(symbole: "sailboat.fill", libelle: "Bateau", motsCles: ["bateau", "voile", "croisiere", "lac "]),
        IconeSouvenir(symbole: "tent.fill", libelle: "Camping", motsCles: ["camping", "tente ", "tentes ", "bivouac"]),
        IconeSouvenir(symbole: "mountain.2.fill", libelle: "Montagne", motsCles: ["montagne", "rando", "alpe", "sommet", "col "]),
        IconeSouvenir(symbole: "figure.skiing.downhill", libelle: "Ski", motsCles: ["ski", "snowboard", "luge"]),
        IconeSouvenir(symbole: "snowflake", libelle: "Hiver", motsCles: ["hiver", "neige"]),
        IconeSouvenir(symbole: "tree.fill", libelle: "Noël", motsCles: ["noel", "christmas", "sapin"]),
        IconeSouvenir(symbole: "graduationcap.fill", libelle: "École", motsCles: ["ecole", "rentree", "diplome", "promotion", "remise des"]),
        IconeSouvenir(symbole: "figure.run", libelle: "Sport", motsCles: ["sport", "course", "marathon", "tennis", "judo", "velo"]),
        IconeSouvenir(symbole: "soccerball", libelle: "Foot", motsCles: ["foot", "match"]),
        IconeSouvenir(symbole: "theatermasks.fill", libelle: "Spectacle", motsCles: ["spectacle", "theatre", "danse", "gala "]),
        IconeSouvenir(symbole: "music.mic", libelle: "Musique", motsCles: ["concert", "musique", "chorale", "piano", "guitare"]),
        IconeSouvenir(symbole: "pawprint.fill", libelle: "Animaux", motsCles: ["chat ", "chats ", "chien", "animaux", "zoo ", "cheval"]),
        IconeSouvenir(symbole: "house.fill", libelle: "Maison", motsCles: ["maison", "demenagement", "jardin"]),
        IconeSouvenir(symbole: "figure.2.and.child.holdinghands", libelle: "Famille", motsCles: ["famille", "cousin", "grands-parents", "mamie", "papi"]),
        IconeSouvenir(symbole: "sparkles", libelle: "Souvenirs", motsCles: ["souvenir", "coucher de soleil"]),
        IconeSouvenir(symbole: "film.stack", libelle: "Film", motsCles: ["film", "montage"]),
    ]

    /// Sans rien de reconnu : un souvenir.
    public static let parDefaut = "sparkles"

    public static func libelle(_ symbole: String) -> String {
        toutes.first { $0.symbole == symbole }?.libelle ?? "Souvenirs"
    }

    /// L'icône que le nom évoque ; `nil` s'il n'évoque rien. Sans accents ni majuscules : « Noël » comme « noel ». Un mot-clé
    /// est le début d'un mot (« anniv » pour « anniversaire ») ; terminé par une espace, il doit être le mot entier (« mer »,
    /// pas « merveilleux »).
    public static func suggerer(_ texte: String) -> String? {
        let propre = " " + texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CH"))
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ") + " "
        // Le mot le plus tôt dans le nom l'emporte : « Anniversaire à la plage » est un anniversaire.
        var meilleure: (position: String.Index, symbole: String)?
        for icone in toutes {
            for mot in icone.motsCles {
                guard let trouve = propre.range(of: mot) else { continue }
                // « mer » dans « merveilleux » ne compte pas : le mot doit commencer après un séparateur.
                let avant = propre[propre.index(before: trouve.lowerBound)]
                guard !avant.isLetter else { continue }
                if meilleure == nil || trouve.lowerBound < meilleure!.position { meilleure = (trouve.lowerBound, icone.symbole) }
            }
        }
        return meilleure?.symbole
    }
}

/// Ce que l'utilisateur a choisi pour un album ou une vidéo : l'icône, le titre, la date. Tout est facultatif ; `majLe`
/// départage deux appareils — le choix le plus récent l'emporte, entrée par entrée.
public struct CouvertureSouvenir: Codable, Sendable, Hashable {
    public var symbole: String?
    public var titre: String?
    public var date: Date?
    /// L'image choisie dans la vidéo (8.2), en secondes depuis le début ; absent : l'image de Séance (une seconde).
    public var instantImage: Double?
    public var majLe: Date

    public init(symbole: String? = nil, titre: String? = nil, date: Date? = nil, instantImage: Double? = nil, majLe: Date) {
        self.symbole = symbole
        self.titre = titre
        self.date = date
        self.instantImage = instantImage
        self.majLe = majLe
    }

    /// Rien de choisi : l'entrée ne sert plus qu'à dire « rétabli » aux autres appareils.
    public var estVide: Bool { symbole == nil && (titre ?? "").isEmpty && date == nil && instantImage == nil }
}

/// Toutes les couvertures, par chemin (celui du dossier d'un album, ou d'une vidéo). Elles voyagent dans les réglages
/// synchronisés, sous la clé `cle` ; le format reste additif.
public struct CouverturesSouvenirs: Codable, Sendable, Hashable {
    public static let cle = "videos.couvertures"
    public var entrees: [String: CouvertureSouvenir]

    public init(entrees: [String: CouvertureSouvenir] = [:]) {
        self.entrees = entrees
    }

    public init(donnees: Data?) {
        entrees = donnees.flatMap { try? JSONDecoder().decode(CouverturesSouvenirs.self, from: $0) }?.entrees ?? [:]
    }

    public func encoder() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// La couverture d'un chemin, si quelque chose y est choisi.
    public func couverture(_ chemin: String) -> CouvertureSouvenir? {
        entrees[chemin].flatMap { $0.estVide ? nil : $0 }
    }

    public mutating func choisir(_ chemin: String, symbole: String?, titre: String?, date: Date?, instantImage: Double? = nil,
                                 le maintenant: Date = .now) {
        let titrePropre = titre?.trimmingCharacters(in: .whitespacesAndNewlines)
        entrees[chemin] = CouvertureSouvenir(symbole: symbole, titre: (titrePropre ?? "").isEmpty ? nil : titrePropre, date: date,
                                             instantImage: instantImage, majLe: maintenant)
    }

    /// Revient à ce que Séance propose : l'entrée reste, vide et datée, pour que les autres appareils l'apprennent.
    public mutating func retablir(_ chemin: String, le maintenant: Date = .now) {
        entrees[chemin] = CouvertureSouvenir(majLe: maintenant)
    }

    /// Reprend les choix d'un autre appareil plus récents que les nôtres ; vrai si quelque chose a changé.
    @discardableResult
    public mutating func fusionner(_ autres: CouverturesSouvenirs) -> Bool {
        var change = false
        for (chemin, sienne) in autres.entrees where sienne.majLe > (entrees[chemin]?.majLe ?? .distantPast) {
            entrees[chemin] = sienne
            change = true
        }
        return change
    }
}

/// Un album de souvenirs (6.2) : un dossier d'événement et ses vidéos — ou une vidéo seule, rangée directement à la
/// racine ou dans un dossier d'année (« 2026/Anniversaire de Camille.mp4 »), qui fait carte à elle seule.
public struct AlbumSouvenirs: Sendable, Hashable, Identifiable {
    /// Le chemin du dossier, ou celui de la vidéo seule : c'est aussi la clé de sa couverture.
    public let id: String
    public let titre: String
    public let symbole: String
    /// Dans l'ordre où elles ont été filmées : la plus ancienne d'abord.
    public let videos: [VideoPerso]
    /// La date choisie, ou celles des vidéos.
    public let debut: Date?
    public let fin: Date?
    /// L'année de la section : la date choisie, sinon une année dans le chemin (« 2025/Noël »), sinon celle des vidéos.
    public let annee: Int?
    public let estVideoSeule: Bool

    public var taille: Int64 { videos.reduce(0) { $0 + $1.taille } }

    /// « 12 septembre 2026 », « 1 – 3 août 2026 », « 3 juin – 14 août 2026 », « juin 2025 – août 2026 ».
    public var periode: String? {
        Self.periode(debut, fin) ?? annee.map(String.init)
    }

    public static func periode(_ debut: Date?, _ fin: Date?, calendrier: Calendar = .current) -> String? {
        let suisse = Locale(identifier: "fr_CH")
        func jour(_ date: Date) -> String {
            date.formatted(Date.FormatStyle(timeZone: calendrier.timeZone).day().month(.wide).year().locale(suisse))
        }
        guard let debut, let fin else { return (debut ?? fin).map(jour) }
        if calendrier.isDate(debut, inSameDayAs: fin) { return jour(fin) }
        if calendrier.isDate(debut, equalTo: fin, toGranularity: .month) { return "\(calendrier.component(.day, from: debut)) – " + jour(fin) }
        if calendrier.isDate(debut, equalTo: fin, toGranularity: .year) {
            return debut.formatted(Date.FormatStyle(timeZone: calendrier.timeZone).day().month(.wide).locale(suisse)) + " – " + jour(fin)
        }
        let mois = Date.FormatStyle(timeZone: calendrier.timeZone).month(.wide).year().locale(suisse)
        return debut.formatted(mois) + " – " + fin.formatted(mois)
    }
}

extension ArbreVideosPerso {
    /// Les albums, du plus récent au plus ancien.
    public func albums(couvertures: CouverturesSouvenirs = CouverturesSouvenirs(), calendrier: Calendar = .current) -> [AlbumSouvenirs] {
        var parCle: [String: [VideoPerso]] = [:]
        for video in videos { parCle[Self.cleAlbum(video), default: []].append(video) }
        return parCle.map { cle, contenu in
            let seule = contenu.count == 1 && contenu[0].chemin == cle
            let choisie = couvertures.couverture(cle)
            let nomParDefaut = seule ? contenu[0].nom : (cle as NSString).lastPathComponent
            let titre = choisie?.titre ?? nomParDefaut
            // La date d'un fichier est souvent celle de sa copie sur le NAS : quand elle contredit l'année écrite dans le
            // chemin (« 2025/Ski à Verbier », copié en 2026), c'est le chemin qui dit vrai, et l'album ne montre que l'année.
            let anneeChemin = Self.anneeDansLeChemin(cle)
            let dates = contenu.compactMap(\.modifieLe).filter { anneeChemin == nil || calendrier.component(.year, from: $0) == anneeChemin }
            let debut = choisie?.date ?? dates.min()
            let fin = choisie?.date ?? dates.max()
            let annee = choisie?.date.map { calendrier.component(.year, from: $0) } ?? anneeChemin ?? fin.map { calendrier.component(.year, from: $0) }
            let symbole = choisie?.symbole ?? IconesSouvenirs.suggerer(titre) ?? IconesSouvenirs.suggerer(cle) ?? IconesSouvenirs.parDefaut
            let ordonnees = contenu.sorted { ($0.modifieLe ?? .distantPast, $0.nom) < ($1.modifieLe ?? .distantPast, $1.nom) }
            return AlbumSouvenirs(id: cle, titre: titre, symbole: symbole, videos: ordonnees, debut: debut, fin: fin, annee: annee, estVideoSeule: seule)
        }
        .sorted { ($0.annee ?? 0, $0.fin ?? .distantPast, $1.titre) > ($1.annee ?? 0, $1.fin ?? .distantPast, $0.titre) }
    }

    /// Les albums rangés par année, la plus récente d'abord ; ceux sans date à la fin, dans « Sans date ».
    public static func parAnnee(_ albums: [AlbumSouvenirs]) -> [(titre: String, albums: [AlbumSouvenirs])] {
        let groupes = Dictionary(grouping: albums) { $0.annee }
        return groupes.keys.sorted { ($0 ?? Int.min) > ($1 ?? Int.min) }.map { annee in
            (annee.map(String.init) ?? "Sans date", groupes[annee] ?? [])
        }
    }

    /// L'icône d'une vidéo dans son album : la sienne si elle en a une, celle que son nom évoque, sinon celle de l'album.
    public static func symbole(de video: VideoPerso, dans album: AlbumSouvenirs, couvertures: CouverturesSouvenirs) -> String {
        couvertures.couverture(video.chemin)?.symbole ?? (album.estVideoSeule ? album.symbole : IconesSouvenirs.suggerer(video.nom)) ?? album.symbole
    }

    /// Une vidéo appartient à l'album de son dossier ; directement à la racine ou dans un dossier d'année, elle est seule.
    static func cleAlbum(_ video: VideoPerso) -> String {
        let dossier = video.dossier
        guard !dossier.isEmpty, !estAnnee((dossier as NSString).lastPathComponent) else { return video.chemin }
        return dossier
    }

    static func estAnnee(_ texte: String) -> Bool {
        texte.count == 4 && Int(texte).map { (1900...2100).contains($0) } == true
    }

    /// La dernière année écrite dans le chemin : « 2025/Noël » → 2025, « Film de famille 2010-2020 » → 2020.
    static func anneeDansLeChemin(_ chemin: String) -> Int? {
        let mots = chemin.split { !$0.isNumber }.map(String.init)
        return mots.last(where: estAnnee).flatMap(Int.init)
    }
}

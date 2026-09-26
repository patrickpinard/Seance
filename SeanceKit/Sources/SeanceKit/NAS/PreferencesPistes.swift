import Foundation

/// La langue et les sous-titres qu'on veut retrouver à chaque film (8.1), par profil : le lecteur les choisit tout seul
/// dès que VLC annonce les pistes du fichier. Le panneau « Langue et sous-titres » reste là pour changer d'avis.
public struct PreferencesPistes: Codable, Sendable, Hashable {
    public enum SousTitres: String, Codable, Sendable, CaseIterable {
        /// Jamais de sous-titres, même en version originale.
        case jamais
        /// Seulement quand la piste audio n'est pas dans la langue voulue : la VO sous-titrée.
        case siLangueEtrangere
        case toujours

        public var nom: String {
            switch self {
            case .jamais: "Jamais"
            case .siLangueEtrangere: "En version originale seulement"
            case .toujours: "Toujours"
            }
        }
    }

    /// Code de langue (« fr », « en »…) ; vide : la piste du fichier, telle quelle (souvent la version originale).
    public var audio: String
    public var sousTitres: SousTitres
    /// La langue des sous-titres.
    public var langueSousTitres: String

    public init(audio: String = "fr", sousTitres: SousTitres = .siLangueEtrangere, langueSousTitres: String = "fr") {
        self.audio = audio
        self.sousTitres = sousTitres
        self.langueSousTitres = langueSousTitres
    }

    /// Les langues proposées dans les réglages.
    public static let langues: [(code: String, nom: String)] = [
        ("fr", "Français"), ("en", "Anglais"), ("de", "Allemand"), ("it", "Italien"), ("es", "Espagnol"),
    ]

    /// Une piste telle que VLC la décrit : son identifiant, son nom affiché, sa langue quand le fichier la donne.
    public struct Piste: Sendable, Hashable {
        public let id: String
        public let nom: String
        public let langue: String?

        public init(id: String, nom: String, langue: String?) {
            self.id = id
            self.nom = nom
            self.langue = langue
        }

        /// La langue de la piste en code court, lue dans sa langue déclarée ou, à défaut, dans son nom.
        public var code: String? {
            if let langue, let code = PreferencesPistes.code(langue) { return code }
            return PreferencesPistes.code(nom)
        }
    }

    /// Ce qu'il faut sélectionner : la piste audio (`nil` : garder celle du fichier), et les sous-titres —
    /// `.aucun` pour les couper, `.piste(id)` pour en choisir, `.garder` pour ne pas y toucher.
    public enum ChoixSousTitres: Sendable, Equatable {
        case garder, aucun, piste(String)
    }

    public func choisir(audio pistesAudio: [Piste], sousTitres pistesTexte: [Piste],
                        audioActuelle: String?) -> (audio: String?, sousTitres: ChoixSousTitres) {
        let voulue = audio.isEmpty ? nil : pistesAudio.first { $0.code == audio }
        let audioRetenue = voulue ?? pistesAudio.first { $0.id == audioActuelle } ?? pistesAudio.first
        // L'audio est dans la langue voulue quand on l'a trouvée ; sinon, c'est la VO.
        let enLangueVoulue = audio.isEmpty ? audioRetenue?.code == langueSousTitres : voulue != nil
        let texte = pistesTexte.first { $0.code == langueSousTitres }
        let choixTexte: ChoixSousTitres
        switch sousTitres {
        case .jamais:
            choixTexte = .aucun
        case .toujours:
            choixTexte = texte.map { .piste($0.id) } ?? .garder
        case .siLangueEtrangere:
            choixTexte = enLangueVoulue ? .aucun : (texte.map { .piste($0.id) } ?? .garder)
        }
        return (voulue?.id, choixTexte)
    }

    /// « fre », « fra », « French », « Français », « VF » deviennent « fr » ; pareil pour les autres langues proposées.
    static func code(_ texte: String) -> String? {
        let bas = texte.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        let mots = Set(bas.split { !$0.isLetter }.map(String.init))
        let table: [(String, Set<String>)] = [
            ("fr", ["fr", "fre", "fra", "french", "francais", "vf", "vff", "vfq"]),
            ("en", ["en", "eng", "english", "anglais"]),
            ("de", ["de", "ger", "deu", "german", "deutsch", "allemand"]),
            ("it", ["it", "ita", "italian", "italiano", "italien"]),
            ("es", ["es", "spa", "spanish", "espanol", "espagnol"]),
        ]
        return table.first { !$0.1.isDisjoint(with: mots) }?.0
    }

    /// Réglages de l'appareil : une clé par profil de la famille (vide pour le profil principal).
    public static func cle(profil: String) -> String {
        profil.isEmpty ? "lecture.pistes" : "lecture.pistes.\(profil)"
    }

    public static func lire(_ defauts: UserDefaults = .standard, profil: String) -> PreferencesPistes {
        defauts.data(forKey: cle(profil: profil)).flatMap { try? JSONDecoder().decode(PreferencesPistes.self, from: $0) }
            ?? PreferencesPistes()
    }

    public func enregistrer(_ defauts: UserDefaults = .standard, profil: String) {
        defauts.set(try? JSONEncoder().encode(self), forKey: Self.cle(profil: profil))
    }
}

/// La fin d'une vidéo (8.1) : au-delà de 90 %, ou dans les quatre dernières minutes d'un long film (le générique), le
/// film ou l'épisode compte comme vu, sans question.
public enum FinDeLecture {
    public static func presqueFini(secondes: Double, duree: Double) -> Bool {
        guard duree >= 120, secondes > 0 else { return false }
        if secondes / duree >= 0.9 { return true }
        return duree >= 40 * 60 && duree - secondes <= 4 * 60
    }

    /// Le compte à rebours avant l'épisode suivant.
    public static let delaiEpisodeSuivant = 10
}

import Foundation

public struct ChaineGuide: Sendable, Hashable, Identifiable {
    /// Identifiant XMLTV, par exemple `M6.fr`.
    public let id: String
    public let nom: String

    public init(id: String, nom: String) {
        self.id = id
        self.nom = nom
    }

    /// Chaînes de la TNT française reçues en Suisse romande (EF-45). XML TV Fr garde pour TFX
    /// l'identifiant historique de NT1.
    public static let tntParDefaut: [ChaineGuide] = [
        ChaineGuide(id: "TF1.fr", nom: "TF1"),
        ChaineGuide(id: "France2.fr", nom: "France 2"),
        ChaineGuide(id: "France3.fr", nom: "France 3"),
        ChaineGuide(id: "France5.fr", nom: "France 5"),
        ChaineGuide(id: "M6.fr", nom: "M6"),
        ChaineGuide(id: "Arte.fr", nom: "Arte"),
        ChaineGuide(id: "W9.fr", nom: "W9"),
        ChaineGuide(id: "TMC.fr", nom: "TMC"),
        ChaineGuide(id: "NT1.fr", nom: "TFX"),
        ChaineGuide(id: "6ter.fr", nom: "6ter"),
    ]

    /// Chaînes de la RTS : elles ne sont que dans le fichier complet de XML TV Fr.
    public static let suisses: [ChaineGuide] = [
        ChaineGuide(id: "RTSUn.ch", nom: "RTS 1"),
        ChaineGuide(id: "RTSDeux.ch", nom: "RTS 2"),
    ]

    /// Toutes les chaînes proposées dans les réglages.
    public static var catalogue: [ChaineGuide] { suisses + tntParDefaut }

    /// Cochées au premier lancement : RTS, TF1, France 2, France 3, M6 et Arte.
    public static var parDefaut: [ChaineGuide] {
        let ids: Set = ["RTSUn.ch", "RTSDeux.ch", "TF1.fr", "France2.fr", "France3.fr", "M6.fr", "Arte.fr"]
        return catalogue.filter { ids.contains($0.id) }
    }
}

public struct ProgrammeTV: Sendable, Hashable {
    public enum Nature: String, Sendable, Hashable, CaseIterable {
        case film
        case serie
        case autre
    }

    public var chaine: String
    public var debut: Date
    public var fin: Date
    public var titre: String
    public var sousTitre: String?
    public var description: String?
    public var categories: [String] = []
    /// Année de production (`<date>`). Pour une série, c'est celle de l'épisode.
    public var annee: Int?
    public var saison: Int?
    public var episode: Int?
    public var realisateurs: [String] = []
    public var acteurs: [String] = []
    public var image: URL?

    public init(chaine: String, debut: Date, fin: Date, titre: String, categories: [String] = [], annee: Int? = nil) {
        self.chaine = chaine
        self.debut = debut
        self.fin = fin
        self.titre = titre
        self.categories = categories
        self.annee = annee
    }

    public var dureeMinutes: Int {
        Int(fin.timeIntervalSince(debut) / 60)
    }

    /// Déduite de la première catégorie : XML TV Fr écrit « Film », « Cinéma », « Série »,
    /// « Série TV », « Series », « Série Dramatique »…
    public var nature: Nature {
        guard let premiere = categories.first else { return .autre }
        let c = premiere.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        if c.hasPrefix("film") || c.hasPrefix("cinema") || c.hasPrefix("telefilm") { return .film }
        if c.hasPrefix("serie") { return .serie }
        return .autre
    }
}

/// Lecture d'un guide XMLTV en flux, sans construire d'arbre du document en mémoire.
public enum XMLTV {
    public struct Resultat: Sendable {
        public var chaines: [ChaineGuide]
        public var programmes: [ProgrammeTV]
    }

    public enum Erreur: Error, Equatable {
        case xmlInvalide(ligne: Int, message: String)
    }

    /// - Parameter retenues: identifiants des chaînes à garder ; `nil` garde tout.
    public static func lire(_ donnees: Data, chaines retenues: Set<String>? = nil) throws -> Resultat {
        let lecteur = LecteurXMLTV(retenues: retenues)
        let parseur = XMLParser(data: donnees)
        parseur.delegate = lecteur
        parseur.shouldResolveExternalEntities = false
        guard parseur.parse() else {
            throw Erreur.xmlInvalide(
                ligne: parseur.lineNumber,
                message: parseur.parserError?.localizedDescription ?? "erreur inconnue"
            )
        }
        return Resultat(chaines: lecteur.chaines, programmes: lecteur.programmes)
    }

    /// `20260917211000 +0200`, parfois sans décalage horaire (heure de Paris par défaut).
    static func date(_ texte: String) -> Date? {
        let texte = texte.trimmingCharacters(in: .whitespaces)
        let formateur = DateFormatter()
        formateur.locale = Locale(identifier: "en_US_POSIX")
        formateur.dateFormat = "yyyyMMddHHmmss Z"
        if let date = formateur.date(from: texte) { return date }
        formateur.dateFormat = "yyyyMMddHHmmss"
        formateur.timeZone = TimeZone(identifier: "Europe/Paris")
        return formateur.date(from: String(texte.prefix(14)))
    }

    /// `xmltv_ns` numérote à partir de zéro : « 19.18. » désigne la saison 20, épisode 19.
    /// `onscreen` s'écrit « S20E19 ».
    static func numeroEpisode(_ texte: String, systeme: String?) -> (saison: Int?, episode: Int?) {
        if systeme == "xmltv_ns" {
            let parties = texte.split(separator: ".", omittingEmptySubsequences: false)
            func numero(_ i: Int) -> Int? {
                guard parties.count > i else { return nil }
                let avantBarre = parties[i].split(separator: "/").first ?? ""
                return Int(avantBarre.trimmingCharacters(in: .whitespaces)).map { $0 + 1 }
            }
            return (numero(0), numero(1))
        }
        let chiffres = texte.uppercased().split(whereSeparator: { !$0.isNumber && $0 != "S" && $0 != "E" })
        guard let bloc = chiffres.first(where: { $0.hasPrefix("S") && $0.contains("E") }) else { return (nil, nil) }
        let morceaux = bloc.dropFirst().split(separator: "E")
        return (morceaux.first.flatMap { Int($0) }, morceaux.count > 1 ? Int(morceaux[1]) : nil)
    }
}

private final class LecteurXMLTV: NSObject, XMLParserDelegate {
    let retenues: Set<String>?
    var chaines: [ChaineGuide] = []
    var programmes: [ProgrammeTV] = []

    private var pile: [String] = []
    private var texte = ""
    private var chaineEnCours: String?
    private var nomChaineEnCours: String?
    private var programme: ProgrammeTV?
    private var systemeEpisode: String?

    init(retenues: Set<String>?) {
        self.retenues = retenues
    }

    private func estRetenue(_ id: String) -> Bool {
        retenues?.contains(id) ?? true
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        let parent = pile.last
        pile.append(element)
        texte = ""
        switch element {
        case "channel":
            chaineEnCours = attributes["id"]
            nomChaineEnCours = nil
        case "programme":
            guard let chaine = attributes["channel"], estRetenue(chaine),
                  let debut = attributes["start"].flatMap(XMLTV.date),
                  let fin = attributes["stop"].flatMap(XMLTV.date)
            else {
                programme = nil
                return
            }
            programme = ProgrammeTV(chaine: chaine, debut: debut, fin: fin, titre: "")
        case "episode-num":
            systemeEpisode = attributes["system"]
        case "icon" where parent == "programme":
            programme?.image = attributes["src"].flatMap(URL.init(string:))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        texte += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        pile.removeLast()
        let valeur = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        texte = ""

        if chaineEnCours != nil {
            switch element {
            case "display-name" where nomChaineEnCours == nil:
                nomChaineEnCours = valeur
            case "channel":
                if let id = chaineEnCours, estRetenue(id) {
                    chaines.append(ChaineGuide(id: id, nom: nomChaineEnCours ?? id))
                }
                chaineEnCours = nil
            default:
                break
            }
            return
        }

        guard programme != nil else { return }
        switch element {
        case "title" where programme?.titre.isEmpty == true:
            programme?.titre = valeur
        case "sub-title":
            programme?.sousTitre = valeur
        case "desc":
            programme?.description = valeur
        case "category":
            programme?.categories.append(valeur)
        case "date":
            programme?.annee = Int(valeur.prefix(4))
        case "director":
            programme?.realisateurs.append(valeur)
        case "actor":
            programme?.acteurs.append(valeur)
        case "episode-num":
            // Le premier système de numérotation rencontré l'emporte.
            let numero = XMLTV.numeroEpisode(valeur, systeme: systemeEpisode)
            if programme?.saison == nil { programme?.saison = numero.saison }
            if programme?.episode == nil { programme?.episode = numero.episode }
        case "programme":
            if let termine = programme, !termine.titre.isEmpty {
                programmes.append(termine)
            }
            programme = nil
        default:
            break
        }
    }
}

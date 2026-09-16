import Foundation

/// Ce qu'on déduit du chemin d'un fichier vidéo du NAS (modes dossier partagé et index JSON).
public struct FichierVideoAnalyse: Sendable, Hashable {
    public var type: TypeTitre
    public var titre: String
    public var annee: Int?
    public var episode: NumeroEpisode?
    public var qualite: QualiteVideo?
    /// Identifiant TMDB écrit dans le nom, par exemple « [tmdbid-603] » (convention Jellyfin).
    public var tmdbID: Int?
}

/// Lit des noms comme « John Wick (2014) 2160p.mkv », « La.Chute.de.Londres.2016.1080p.BluRay.mkv »
/// ou « Reacher (2022)/Season 01/Reacher - S01E03.mkv ».
public enum AnalyseNomFichier {
    public static let extensionsVideo: Set<String> = ["mkv", "mp4", "m4v", "avi", "mov", "ts", "m2ts", "wmv", "webm"]

    /// `nil` pour un fichier qui n'est pas une vidéo, ou pour un extrait (« sample », « trailer »).
    public static func analyser(chemin: String) -> FichierVideoAnalyse? {
        let url = URL(fileURLWithPath: chemin)
        guard extensionsVideo.contains(url.pathExtension.lowercased()) else { return nil }
        // macOS livre les noms décomposés (« e » + accent) : TMDB ne les retrouve qu'en forme composée.
        let nom = url.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
        let minuscule = nom.lowercased()
        guard !minuscule.contains("sample"), !minuscule.contains("trailer") else { return nil }

        let texte = nom.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        let episode = numeroEpisode(dans: texte)
        let annee = anneeEntreDelimiteurs(dans: texte)
        let qualite = qualite(dans: texte)
        let tmdbID = identifiantTMDB(dans: nom) ?? url.pathComponents.dropLast().reversed().lazy.compactMap(identifiantTMDB).first

        var titre = titreAvantMarqueurs(texte, marqueurs: [episode?.debut, annee?.debut, qualite?.debut, texte.firstIndex(of: "[")])
        if episode != nil, titre.isEmpty {
            // « S01E03.mkv » : le titre est dans le dossier de la série, au-dessus d'un éventuel « Season 01 ».
            titre = dossierDeSerie(url).map(\.precomposedStringWithCanonicalMapping).map { titreAvantMarqueurs($0, marqueurs: [anneeEntreDelimiteurs(dans: $0)?.debut, $0.firstIndex(of: "[")]) } ?? ""
        }
        guard !titre.isEmpty else { return nil }

        return FichierVideoAnalyse(
            type: episode == nil ? .film : .serie,
            titre: titre,
            annee: annee?.valeur,
            episode: episode?.valeur,
            qualite: qualite?.valeur,
            tmdbID: tmdbID
        )
    }

    private struct Trouve<Valeur> {
        let valeur: Valeur
        let debut: String.Index
    }

    private static func numeroEpisode(dans texte: String) -> Trouve<NumeroEpisode>? {
        if let m = texte.firstMatch(of: #/(?i)\bS(\d{1,2})\s?E(\d{1,3})\b/#), let s = Int(m.1), let e = Int(m.2) {
            return Trouve(valeur: NumeroEpisode(saison: s, episode: e), debut: m.range.lowerBound)
        }
        if let m = texte.firstMatch(of: #/\b(\d{1,2})x(\d{2,3})\b/#), let s = Int(m.1), let e = Int(m.2) {
            return Trouve(valeur: NumeroEpisode(saison: s, episode: e), debut: m.range.lowerBound)
        }
        return nil
    }

    /// Une année entre parenthèses, crochets ou espaces, jamais en tête du nom (« 1917 », « 2012 »).
    private static func anneeEntreDelimiteurs(dans texte: String) -> Trouve<Int>? {
        for m in texte.matches(of: #/[\(\[\s]((?:19|20)\d{2})(?=[\)\]\s]|$)/#) {
            guard let annee = Int(m.1), m.range.lowerBound > texte.startIndex else { continue }
            return Trouve(valeur: annee, debut: m.range.lowerBound)
        }
        return nil
    }

    private static func qualite(dans texte: String) -> Trouve<QualiteVideo>? {
        let motifs: [(Regex<Substring>, QualiteVideo)] = [
            (#/(?i)\b(?:2160p|4k|uhd)\b/#, .uhd4K),
            (#/(?i)\b1080[pi]\b/#, .hd1080),
            (#/(?i)\b720p\b/#, .hd720),
            (#/(?i)\b(?:480p|576p|dvdrip)\b/#, .sd),
        ]
        return motifs.compactMap { motif, qualite in
            texte.firstMatch(of: motif).map { Trouve(valeur: qualite, debut: $0.range.lowerBound) }
        }.min { $0.debut < $1.debut }
    }

    private static func identifiantTMDB(dans texte: String) -> Int? {
        texte.firstMatch(of: #/(?i)tmdb(?:id)?[-=](\d+)/#).flatMap { Int($0.1) }
    }

    private static func titreAvantMarqueurs(_ texte: String, marqueurs: [String.Index?]) -> String {
        let fin = marqueurs.compactMap { $0 }.min() ?? texte.endIndex
        return texte[..<fin]
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–([").union(.whitespaces))
    }

    private static func dossierDeSerie(_ url: URL) -> String? {
        let dossiers = url.deletingLastPathComponent().pathComponents.dropFirst()
        return dossiers.reversed().first { dossier in
            dossier.firstMatch(of: #/(?i)^(season|saison|staffel)\s*\d+$/#) == nil
        }
    }
}

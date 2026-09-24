import Foundation
import Testing

/// La charte 8.0 vérifiée sur les sources (prérequis de CLAUDE.md, section « Charte 8.0 ») : comme `AccessibiliteTests`
/// refuse une zone de toucher trop petite, ces tests refusent une couleur ou une taille de texte en dur, un emoji dans
/// l'interface, et l'ancien vocabulaire. Ils lisent les fichiers de l'app, de la TV et des widgets.
@Suite("Charte graphique")
struct CharteTests {
    /// La racine du dépôt, à partir de ce fichier (SeanceKit/Tests/SeanceKitTests/).
    static let racine = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Les fichiers qui ont le droit de nommer des couleurs : les thèmes, et les cartes du bilan rendues en image.
    static let themes: Set<String> = ["Theme.swift", "ModelesWidgets.swift", "BilanAnneeView.swift"]

    /// Une ligne de code d'un fichier d'interface, sans ses commentaires.
    struct Ligne {
        let fichier: String
        let numero: Int
        let code: String
    }

    static func lignes(dans dossiers: [String]) -> [Ligne] {
        var resultat: [Ligne] = []
        for dossier in dossiers {
            let base = racine.appending(path: dossier)
            guard let parcours = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in parcours where url.pathExtension == "swift" {
                guard let texte = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for (rang, ligne) in texte.components(separatedBy: "\n").enumerated() {
                    let nette = ligne.trimmingCharacters(in: .whitespaces)
                    guard !nette.hasPrefix("//") else { continue }
                    // Le code avant un commentaire de fin de ligne (hors chaîne, à peu près : suffisant ici).
                    let code = ligne.range(of: " // ").map { String(ligne[..<$0.lowerBound]) } ?? ligne
                    resultat.append(Ligne(fichier: url.lastPathComponent, numero: rang + 1, code: code))
                }
            }
        }
        return resultat
    }

    /// Le texte entre guillemets d'une ligne : ce que l'interface affiche.
    static func litteraux(_ code: String) -> [String] {
        guard let expression = try? Regex(#""(?:[^"\\]|\\.)*""#) else { return [] }
        return code.matches(of: expression).map { String(code[$0.range]) }
    }

    @Test("Aucune couleur en dur hors des thèmes")
    func couleurs() {
        let fautes = Self.lignes(dans: ["Seance", "SeanceTV", "SeanceWidget"]).filter { ligne in
            !Self.themes.contains(ligne.fichier)
                && ["Color(red:", "Color(white:", "UIColor(red:", "UIColor(white:"].contains { ligne.code.contains($0) }
        }
        #expect(fautes.isEmpty, "Couleurs en dur : \(fautes.map { "\($0.fichier):\($0.numero)" }) — prends un jeton de Theme")
    }

    @Test("Les styles de texte du système sur l'iPhone, l'iPad et les widgets")
    func tailles() throws {
        let enDur = try Regex(#"\.font\(\.system\(size: *[0-9]"#)
        let fautes = Self.lignes(dans: ["Seance", "SeanceWidget"]).filter { ligne in
            !Self.themes.contains(ligne.fichier) && ligne.code.contains(enDur)
        }
        #expect(fautes.isEmpty, "Tailles de texte en dur : \(fautes.map { "\($0.fichier):\($0.numero)" }) — prends un style (.body, .headline…)")
    }

    @Test("Pas d'emoji dans l'interface")
    func emoji() {
        let fautes = Self.lignes(dans: ["Seance", "SeanceTV", "SeanceWidget"]).filter { ligne in
            Self.litteraux(ligne.code).contains { texte in
                texte.unicodeScalars.contains { (0x1F300...0x1FAFF).contains($0.value) }
            }
        }
        #expect(fautes.isEmpty, "Emoji affichés : \(fautes.map { "\($0.fichier):\($0.numero)" }) — un SF Symbol à la place")
    }

    @Test("Le vocabulaire de la charte : « Suggestions », « TV »")
    func vocabulaire() {
        // Les notes de version racontent le passé avec ses mots : elles ne comptent pas.
        let fautes = Self.lignes(dans: ["Seance", "SeanceTV", "SeanceWidget"]).filter { ligne in
            ligne.fichier != "Versions.swift" && Self.litteraux(ligne.code).contains { texte in
                texte.contains("Idées") || texte.contains(" idées") || texte.contains("Télé ") || texte.contains("Télévision")
            }
        }
        #expect(fautes.isEmpty, "Ancien vocabulaire : \(fautes.map { "\($0.fichier):\($0.numero)" })")
    }
}

import SwiftUI

/// Réglages › Versions, sur la TV (6.3) : l'historique de Séance, le même que sur l'iPhone (`NoteVersion.historique`,
/// partagé par `project.yml`). Une ligne par version, refermée au départ pour garder la page courte ; le clic l'ouvre
/// sur ce qu'elle apporte. Chaque version reste un bouton : sur tvOS, une page de texte pur n'a rien à mettre au
/// focus, et la télécommande ne peut plus la faire défiler.
struct PageVersionsTV: View {
    @State private var ouvertes: Set<String> = []

    var body: some View {
        PageTV(titre: "Versions",
               sousTitre: "Ce que chaque version a apporté. Séance \(ReglagesTV.version) sur cette Apple TV.") {
            ForEach(NoteVersion.historique) { version in
                SectionTV(explication: ouvertes.contains(version.numero) ? nil : version.resume) {
                    LigneTVReglage(titre: "Version \(version.numero)", detail: version.date,
                                   symbole: version.numero == ReglagesTV.version ? "checkmark.seal.fill" : "clock.arrow.circlepath",
                                   action: { ouvrirOuFermer(version) }) {
                        BoutTV(forme: .valeur(ouvertes.contains(version.numero) ? "Fermer" : "Voir"))
                    }
                    if ouvertes.contains(version.numero) {
                        ForEach(version.fonctionnalites) { fonctionnalite in
                            LigneTVReglage(titre: fonctionnalite.titre, detail: fonctionnalite.detail,
                                           symbole: fonctionnalite.symbole)
                        }
                    }
                }
            }
        }
    }

    private func ouvrirOuFermer(_ version: NoteVersion) {
        if ouvertes.contains(version.numero) {
            ouvertes.remove(version.numero)
        } else {
            ouvertes.insert(version.numero)
        }
    }
}

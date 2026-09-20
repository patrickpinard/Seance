import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Mes listes sur la TV : à voir, en cours, terminés — une étagère chacune, plus les listes nommées.
struct ListesTV: View {
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    @Query(sort: \ListePerso.nom) private var listes: [ListePerso]
    @Query private var fichiers: [FichierNAS]

    enum Onglet: String, CaseIterable, Hashable {
        case aVoir = "À voir", enCours = "En cours", termines = "Terminés", listes = "Listes"

        var statut: StatutSuivi? {
            switch self {
            case .aVoir: .aVoir
            case .enCours: .enCours
            case .termines: .termine
            case .listes: nil
            }
        }
    }

    @State private var onglet = Onglet.aVoir

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 44) {
                if suivis.isEmpty, listes.isEmpty {
                    VideTV(symbole: "bookmark", titre: "Tes listes sont vides sur cette TV",
                           message: "Elles arrivent de ton iPhone, de ton iPad et de ton Mac. Tu peux aussi garder un titre « à voir » depuis sa fiche, ici même.")
                } else {
                    // Les mêmes onglets que sur l'iPhone (charte graphique).
                    SelecteurTV(selection: $onglet, cases: Onglet.allCases.map { ($0, $0.rawValue) })
                    if onglet == .listes {
                        if listes.allSatisfy(\.titres.isEmpty) {
                            VideTV(symbole: "rectangle.stack", titre: "Aucune liste",
                                   message: "Crée tes listes sur ton iPhone — « Soirées entre amis », « À voir en famille » — elles arriveront ici.")
                        }
                        ForEach(listes.filter { !$0.titres.isEmpty }) { liste in
                            EtagereTV(titre: liste.nom, sousTitre: liste.titres.count > 1 ? "\(liste.titres.count) titres" : "1 titre") {
                                ForEach(liste.apercus, id: \.reference) { apercu in
                                    NavigationLink(value: apercu.reference) {
                                        AfficheTV(titre: apercu.titre, sousTitre: nil, cheminAffiche: apercu.cheminAffiche, marque: marque(apercu.reference))
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                        }
                    } else if let statut = onglet.statut {
                        grille(statut)
                    }
                }
            }
            .padding(.vertical, 40)
        }
    }

    /// Une grille plutôt qu'une rangée : une liste compte parfois des dizaines de titres.
    @ViewBuilder
    private func grille(_ statut: StatutSuivi) -> some View {
        let titres = suivis.filter { $0.statut == statut && !$0.masque }
        if titres.isEmpty {
            VideTV(symbole: onglet == .aVoir ? "bookmark" : onglet == .enCours ? "play.circle" : "checkmark.circle",
                   titre: onglet == .aVoir ? "Rien à voir pour l'instant" : onglet == .enCours ? "Aucune série en cours" : "Rien de terminé",
                   message: onglet == .aVoir ? "Garde un titre depuis sa fiche : il se range ici."
                          : onglet == .enCours ? "Coche un épisode sur la fiche d'une série : elle se range ici."
                          : "Un film vu, une série finie : ils se rangent ici, avec ta note.")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(AfficheTV.largeur), spacing: 40, alignment: .top), count: 6), spacing: 50) {
                ForEach(titres) { suivi in
                    NavigationLink(value: suivi.reference) {
                        AfficheTV(titre: suivi.titre, sousTitre: suivi.note.map { "★ \($0)/10" } ?? (suivi.type == .film ? "Film" : "Série"),
                                  cheminAffiche: suivi.cheminAffiche, marque: marque(suivi.reference))
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 20)
            .focusSection()
        }
    }

    private func marque(_ reference: ReferenceTitre) -> String? {
        fichiers.contains { $0.reference == reference } ? "externaldrive.fill" : nil
    }
}

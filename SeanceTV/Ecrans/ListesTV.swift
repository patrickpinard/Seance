import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Mes listes sur la TV : à voir, en cours, terminés — une étagère chacune, plus les listes nommées.
struct ListesTV: View {
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    @Query(sort: \ListePerso.nom) private var listes: [ListePerso]
    @Query private var fichiers: [FichierNAS]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                if suivis.isEmpty, listes.isEmpty {
                    VideTV(symbole: "bookmark", titre: "Tes listes sont vides sur cette TV",
                           message: "Elles arriveront de ton iPhone, de ton iPad et de ton Mac par le dossier de synchronisation du NAS. Tu peux aussi garder un titre « à voir » depuis sa fiche, ici même.")
                }
                etagere("À voir", .aVoir)
                etagere("En cours", .enCours)
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
                etagere("Terminés", .termine)
            }
            .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private func etagere(_ titre: String, _ statut: StatutSuivi) -> some View {
        let titres = suivis.filter { $0.statut == statut && !$0.masque }
        if !titres.isEmpty {
            EtagereTV(titre: titre, sousTitre: titres.count > 1 ? "\(titres.count) titres" : "1 titre") {
                ForEach(titres.prefix(40)) { suivi in
                    NavigationLink(value: suivi.reference) {
                        AfficheTV(titre: suivi.titre, sousTitre: suivi.note.map { "★ \($0)/10" } ?? (suivi.type == .film ? "Film" : "Série"),
                                  cheminAffiche: suivi.cheminAffiche, marque: marque(suivi.reference))
                    }
                    .buttonStyle(.card)
                }
            }
        }
    }

    private func marque(_ reference: ReferenceTitre) -> String? {
        fichiers.contains { $0.reference == reference } ? "externaldrive.fill" : nil
    }
}

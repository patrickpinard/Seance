import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce que tu as regardé (8.11) : les titres terminés, rangés par mois — celui où tu as fini chaque titre —, avec ce que
/// le mois a compté. L'ancien onglet « Terminés » de Mes listes : sa vraie place est près des statistiques et du bilan.
/// Les titres retirés de l'ancienne liste (`masque`) n'y reviennent pas.
struct HistoriqueView: View {
    @Environment(EtatApp.self) private var etat
    @Query(filter: #Predicate<Suivi> { $0.statutBrut == "termine" && !$0.masque }) private var termines: [Suivi]
    @Query private var visionnages: [Visionnage]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if termines.isEmpty {
                    EtatVide(symbole: "checkmark.circle", titre: "Rien de terminé pour l'instant",
                             message: "Un film marqué vu, une série finie : ils se rangent ici, mois par mois, avec ta note.")
                        .padding(.top, 8)
                } else {
                    let episodes = episodesVus
                    ForEach(TerminesParMois.grouper(termines, fini: { finis[$0.reference] }), id: \.titre) { groupe in
                        enTeteMois(groupe)
                        LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
                            ForEach(groupe.elements) { suivi in
                                NavigationLink(value: suivi.reference) {
                                    CarteLargeTitre(suivi: suivi, episodesVus: episodes[suivi.tmdbID] ?? 0)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    MenuActionsTitre(titre: TitreResume(reference: suivi.reference, titre: suivi.titre,
                                                                        cheminAffiche: suivi.cheminAffiche, genres: suivi.genres))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.fond)
        .navigationTitle("Ce que tu as regardé")
        .navigationBarTitleDisplayMode(.large)
    }

    /// Le jour où chaque titre terminé l'a été : son dernier visionnage compté (pas « déjà vu avant »).
    private var finis: [ReferenceTitre: Date] {
        var resultat: [ReferenceTitre: Date] = [:]
        for visionnage in visionnages where !visionnage.anterieur {
            let reference = ReferenceTitre(type: visionnage.type, tmdbID: visionnage.tmdbID)
            resultat[reference] = max(resultat[reference] ?? .distantPast, visionnage.vuLe)
        }
        return resultat
    }

    private var episodesVus: [Int: Int] {
        var resultat: [Int: Int] = [:]
        for visionnage in visionnages where visionnage.typeBrut == TypeTitre.serie.rawValue {
            resultat[visionnage.tmdbID, default: 0] += 1
        }
        return resultat
    }

    /// « Septembre 2026 » et, à droite, « 3 films · 1 série · 7 h 40 » : ce que le mois a compté.
    private func enTeteMois(_ groupe: TerminesParMois.Groupe<Suivi>) -> some View {
        let films = groupe.elements.filter { $0.type == .film }.count
        let series = groupe.elements.count - films
        var morceaux = [films > 0 ? Format.pluriel(films, "film") : nil, series > 0 ? Format.pluriel(series, "série") : nil].compactMap { $0 }
        if let mois = groupe.mois {
            let references = Set(groupe.elements.map(\.reference))
            let calendrier = Calendar.current
            let minutes = visionnages.filter {
                !$0.anterieur && references.contains(ReferenceTitre(type: $0.type, tmdbID: $0.tmdbID))
                    && calendrier.isDate($0.vuLe, equalTo: mois, toGranularity: .month)
            }.reduce(0) { $0 + $1.dureeMinutes }
            if minutes > 0 { morceaux.append(HeuresTele.duree(minutes)) }
        }
        return HStack(alignment: .firstTextBaseline) {
            Text(groupe.titre).font(.title3.weight(.bold))
            Spacer(minLength: 8)
            Text(morceaux.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Streaming sur la TV (7.0, maquette 1 du menu) : ce que tes abonnements proposent, et rien d'autre. D'abord les
/// nouveautés de toutes tes plateformes, puis une étagère par plateforme.
struct StreamingTV: View {
    @Environment(EtatTV.self) private var etat
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]

    @State private var toutes: [ApercuTV] = []
    @State private var parPlateforme: [Int: [ApercuTV]] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                if abonnements.isEmpty {
                    VideTV(symbole: "play.rectangle.on.rectangle", titre: "Aucune plateforme cochée",
                           message: "Coche tes abonnements dans Réglages › Plateformes, sur cette TV ou sur ton iPhone : cette page montrera ce qu'ils proposent de nouveau.")
                } else {
                    etagere("Nouveau sur tes plateformes", abonnements.map(\.nom).joined(separator: ", "), toutes)
                    ForEach(abonnements) { abonnement in
                        etagere("Sur \(abonnement.nom)", "Sorties et nouveaux épisodes du mois", parPlateforme[abonnement.providerID] ?? [])
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .task(id: abonnements.map(\.providerID)) { await charger() }
    }

    @ViewBuilder
    private func etagere(_ titre: String, _ sousTitre: String, _ apercus: [ApercuTV]) -> some View {
        if !apercus.isEmpty {
            EtagereTV(titre: titre, sousTitre: sousTitre) {
                ForEach(apercus) { apercu in
                    NavigationLink(value: apercu.reference) {
                        CarteLargeTV(surtitre: nil, titre: apercu.titre, detail: apercu.sousTitre,
                                     cheminImage: apercu.cheminFond ?? apercu.cheminAffiche, marque: nil,
                                     largeur: CarteLargeTV.largeurGrille, reference: apercu.reference)
                    }
                    .buttonStyle(.card)
                }
            }
        }
    }

    private static func criteres(_ type: TypeTitre, _ plateformes: [Int]) -> CriteresDecouverte {
        var criteres = CriteresDecouverte.duMoment(type)
        criteres.fournisseurs = plateformes
        criteres.monetisations = [.abonnement, .gratuit, .avecPublicite]
        return criteres
    }

    private func charger() async {
        guard let client = etat.tmdb, !abonnements.isEmpty else { return }
        let ids = abonnements.map(\.providerID)
        async let films = try? client.decouvrirFilms(Self.criteres(.film, ids))
        async let series = try? client.decouvrirSeries(Self.criteres(.serie, ids))
        toutes = ApercuTV.meler((await films)?.resultats ?? [], (await series)?.resultats ?? [])
        for id in ids {
            async let films = try? client.decouvrirFilms(Self.criteres(.film, [id]))
            async let series = try? client.decouvrirSeries(Self.criteres(.serie, [id]))
            parPlateforme[id] = ApercuTV.meler((await films)?.resultats ?? [], (await series)?.resultats ?? [])
        }
    }
}

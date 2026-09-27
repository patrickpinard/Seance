import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Regarder › Streaming sur la TV (8.0) : ce que tes abonnements proposent, et rien d'autre. D'abord les nouveautés de
/// toutes tes plateformes, puis une étagère par plateforme. Des sections : Regarder les empile dans sa page.
struct SectionsStreamingTV: View {
    @Environment(EtatTV.self) private var etat
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]

    @State private var toutes: [ApercuTV] = []
    /// Déjà vus, refusés ou « pas intéressé pour l'instant » (8.2.15) : comme sur l'iPhone, plus proposés ici.
    @Query(filter: #Predicate<Suivi> { $0.statutBrut == "exclu" || $0.exclusionLangue || $0.statutBrut == "termine" })
    private var suivisEcartes: [Suivi]
    @AppStorage(PasInteresse.cle) private var pasInteresse = ""
    private var ecartes: Set<ReferenceTitre> { Set(suivisEcartes.map(\.reference)).union(PasInteresse.references(pasInteresse)) }
    @State private var parPlateforme: [Int: [ApercuTV]] = [:]
    /// Maquette 8.0, n° 6 : les logos filtrent les plateformes ; `nil`, toutes.
    @State private var plateforme: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
                if abonnements.isEmpty {
                    VideTV(symbole: "play.rectangle.on.rectangle", titre: "Aucune plateforme cochée",
                           message: "Coche tes abonnements dans Réglages › Plateformes, sur cette TV ou sur ton iPhone : cette page montrera ce qu'ils proposent de nouveau.")
                } else {
                    logos
                    if let plateforme, let abonnement = abonnements.first(where: { $0.providerID == plateforme }) {
                        etagere("Nouveau sur \(CarteLargeTV.nomCourt(abonnement.nom))", "Sorties et nouveaux épisodes du mois",
                                parPlateforme[plateforme] ?? [])
                    } else {
                        etagere("Nouveau sur tes plateformes", abonnements.map(\.nom).joined(separator: ", "), toutes)
                        ForEach(abonnements) { abonnement in
                            etagere("Sur \(CarteLargeTV.nomCourt(abonnement.nom))", "Sorties et nouveaux épisodes du mois",
                                    parPlateforme[abonnement.providerID] ?? [])
                        }
                    }
                }
        }
        .task(id: abonnements.map(\.providerID)) { await charger() }
    }

    /// Tout, puis un bouton par plateforme, son logo devant son nom.
    private var logos: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                Button("Tout") { plateforme = nil }
                    .buttonStyle(BoutonTV(principal: plateforme == nil, hauteur: 60))
                ForEach(abonnements) { abonnement in
                    Button { plateforme = abonnement.providerID } label: {
                        HStack(spacing: 12) {
                            ImageTV(url: ImageTMDB.url(abonnement.cheminLogo, .logo), symboleVide: "play.tv")
                                .frame(width: 38, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Text(CarteLargeTV.nomCourt(abonnement.nom))
                        }
                    }
                    .buttonStyle(BoutonTV(principal: plateforme == abonnement.providerID, hauteur: 60))
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    @ViewBuilder
    private func etagere(_ titre: String, _ sousTitre: String, _ tous: [ApercuTV]) -> some View {
        let ecartes = ecartes
        let apercus = tous.filter { !ecartes.contains($0.reference) }
        if !apercus.isEmpty {
            EtagereTV(titre: titre, sousTitre: sousTitre) {
                ForEach(apercus) { apercu in
                    NavigationLink(value: apercu.reference) {
                        CarteLargeTV(surtitre: nil, titre: apercu.titre, detail: apercu.sousTitre,
                                     cheminImage: apercu.cheminFond ?? apercu.cheminAffiche, marque: nil,
                                     largeur: CarteLargeTV.largeurGrille, reference: apercu.reference)
                    }
                    .buttonStyle(.card)
                    .menuCarteTV(apercu.reference, titre: apercu.titre, cheminAffiche: apercu.cheminAffiche)
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

    /// 8.1 : les listes lues sont gardées quatre heures — la page se rouvre aussitôt, sans redemander TMDB à chaque
    /// visite (deux requêtes par plateforme).
    @MainActor
    private enum Memoire {
        static var lues: (ids: [Int], toutes: [ApercuTV], parPlateforme: [Int: [ApercuTV]], le: Date)?
        static let duree: TimeInterval = 4 * 3600
    }

    private func charger() async {
        guard let client = etat.tmdb, !abonnements.isEmpty else { return }
        let ids = abonnements.map(\.providerID)
        if let lues = Memoire.lues, lues.ids == ids, Date.now.timeIntervalSince(lues.le) < Memoire.duree {
            toutes = lues.toutes
            parPlateforme = lues.parPlateforme
            return
        }
        async let films = try? client.decouvrirFilms(Self.criteres(.film, ids))
        async let series = try? client.decouvrirSeries(Self.criteres(.serie, ids))
        toutes = ApercuTV.meler((await films)?.resultats ?? [], (await series)?.resultats ?? [])
        for id in ids {
            async let films = try? client.decouvrirFilms(Self.criteres(.film, [id]))
            async let series = try? client.decouvrirSeries(Self.criteres(.serie, [id]))
            parPlateforme[id] = ApercuTV.meler((await films)?.resultats ?? [], (await series)?.resultats ?? [])
        }
        // Rien de gardé si TMDB n'a rien rendu : la prochaine visite réessaiera.
        if !toutes.isEmpty { Memoire.lues = (ids, toutes, parPlateforme, .now) }
    }
}

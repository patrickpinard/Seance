import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// L'accueil de la TV : la soirée d'abord, puis ce qui se regarde tout de suite (le NAS), puis de quoi choisir.
struct AccueilTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var soirees: [SelectionSoir]
    @Query(sort: \FichierNAS.indexeLe, order: .reverse) private var fichiers: [FichierNAS]
    @Query private var suivis: [Suivi]

    @State private var duMoment: [ApercuTV] = []
    @State private var top: [ApercuTV] = []
    @State private var configuration = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                if etat.tmdb == nil {
                    VStack(spacing: 10) {
                        VideTV(symbole: "iphone.and.arrow.forward", titre: "Séance n'est pas encore configurée sur cette TV",
                               message: "Le plus simple : envoie tout depuis ton iPhone — la clé TMDB, ton NAS et tes listes — avec un code à six chiffres.")
                            .padding(.bottom, -90)
                        Button { configuration = true } label: { Label("Configurer depuis mon iPhone", systemImage: "iphone.and.arrow.forward") }
                            .buttonStyle(BoutonTV(principal: true))
                    }
                    .frame(maxWidth: .infinity)
                }
                if !ceSoir.isEmpty {
                    EtagereTV(titre: "Ce soir", sousTitre: "Ce que tu as prévu de regarder") {
                        ForEach(ceSoir, id: \.reference) { selection in
                            NavigationLink(value: selection.reference) {
                                AfficheTV(titre: selection.titre, sousTitre: surLeNAS(selection.reference) ? "Sur ton NAS" : nil,
                                          cheminAffiche: selection.cheminAffiche, marque: surLeNAS(selection.reference) ? "externaldrive.fill" : nil)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                if !nouveautesNAS.isEmpty {
                    EtagereTV(titre: "Nouveaux sur ton NAS", sousTitre: "Prêts à regarder, du plus récent au plus ancien") {
                        ForEach(nouveautesNAS, id: \.reference) { oeuvre in
                            NavigationLink(value: oeuvre.reference) {
                                AfficheTV(titre: oeuvre.titre, sousTitre: oeuvre.detail, cheminAffiche: oeuvre.cheminAffiche, marque: marque(oeuvre.reference))
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                if !aVoir.isEmpty {
                    EtagereTV(titre: "Dans ta liste", sousTitre: "À voir, du plus récent au plus ancien") {
                        ForEach(aVoir) { suivi in
                            NavigationLink(value: suivi.reference) {
                                AfficheTV(titre: suivi.titre, sousTitre: surLeNAS(suivi.reference) ? "Sur ton NAS" : nil,
                                          cheminAffiche: suivi.cheminAffiche, marque: surLeNAS(suivi.reference) ? "externaldrive.fill" : nil)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                etagere("Du moment", "Sorties et nouveaux épisodes du mois, les plus populaires d'abord", duMoment)
                etagere("Top de l'année", "Les mieux notés sur TMDB depuis un an", top)
            }
            .padding(.vertical, 40)
        }
        .fullScreenCover(isPresented: $configuration) { ConfigurationTV() }
        .task(id: etat.tmdb == nil) { await charger() }
    }

    @ViewBuilder
    private func etagere(_ titre: String, _ sousTitre: String, _ apercus: [ApercuTV]) -> some View {
        if !apercus.isEmpty {
            EtagereTV(titre: titre, sousTitre: sousTitre) {
                ForEach(apercus) { apercu in
                    NavigationLink(value: apercu.reference) {
                        AfficheTV(titre: apercu.titre, sousTitre: apercu.sousTitre, cheminAffiche: apercu.cheminAffiche, marque: marque(apercu.reference))
                    }
                    .buttonStyle(.card)
                }
            }
        }
    }

    // MARK: Données

    private var ceSoir: [SelectionSoir] {
        let soiree = ServiceSoiree.soiree()
        return soirees.filter { $0.soiree == soiree }
    }

    private var aVoir: [Suivi] {
        suivis.filter { $0.statut == .aVoir && !$0.masque }.sorted { $0.ajouteLe > $1.ajouteLe }.prefix(20).map { $0 }
    }

    private var nouveautesNAS: [OeuvreTV] { OeuvreTV.regrouper(fichiers).prefix(20).map { $0 } }

    private func surLeNAS(_ reference: ReferenceTitre) -> Bool {
        fichiers.contains { $0.reference == reference }
    }

    /// Sur le NAS d'abord, sinon « dans ta liste ».
    private func marque(_ reference: ReferenceTitre) -> String? {
        if surLeNAS(reference) { return "externaldrive.fill" }
        return suivis.contains { $0.reference == reference } ? "bookmark.fill" : nil
    }

    private func charger() async {
        guard let client = etat.tmdb else { return }
        async let films = try? client.decouvrirFilms(.duMoment(.film))
        async let series = try? client.decouvrirSeries(.duMoment(.serie))
        async let topFilms = try? client.decouvrirFilms(.top(.film))
        async let topSeries = try? client.decouvrirSeries(.top(.serie))
        duMoment = ApercuTV.meler((await films)?.resultats ?? [], (await series)?.resultats ?? [])
        top = ApercuTV.meler((await topFilms)?.resultats ?? [], (await topSeries)?.resultats ?? [])
    }
}

/// Un titre à montrer sur une étagère, film ou série.
struct ApercuTV: Identifiable, Hashable {
    let reference: ReferenceTitre
    let titre: String
    let sousTitre: String?
    let cheminAffiche: String?
    let popularite: Double

    var id: ReferenceTitre { reference }

    static func meler(_ films: [FilmResume], _ series: [SerieResume]) -> [ApercuTV] {
        let deFilms = films.map {
            ApercuTV(reference: ReferenceTitre(type: .film, tmdbID: $0.id), titre: $0.titre,
                     sousTitre: ["Film", $0.dateSortie.map { String($0.annee) }].compactMap { $0 }.joined(separator: " · "),
                     cheminAffiche: $0.cheminAffiche, popularite: $0.popularite)
        }
        let deSeries = series.map {
            ApercuTV(reference: ReferenceTitre(type: .serie, tmdbID: $0.id), titre: $0.nom, sousTitre: "Série",
                     cheminAffiche: $0.cheminAffiche, popularite: $0.popularite)
        }
        return (deFilms + deSeries).filter { $0.cheminAffiche != nil }.sorted { $0.popularite > $1.popularite }.prefix(24).map { $0 }
    }
}

/// Une œuvre du NAS : un film, ou une série et tous ses épisodes présents.
struct OeuvreTV: Hashable {
    let reference: ReferenceTitre
    let titre: String
    let cheminAffiche: String?
    let fichiers: Int
    let qualite: String?
    let indexeLe: Date

    var detail: String {
        if reference.type == .serie { return fichiers > 1 ? "\(fichiers) épisodes" : "1 épisode" }
        return qualite ?? "Film"
    }

    /// Du plus récemment arrivé au plus ancien ; les fichiers non reconnus par TMDB n'ont pas de fiche et sont laissés.
    static func regrouper(_ fichiers: [FichierNAS]) -> [OeuvreTV] {
        var parTitre: [ReferenceTitre: [FichierNAS]] = [:]
        for fichier in fichiers {
            guard let reference = fichier.reference else { continue }
            parTitre[reference, default: []].append(fichier)
        }
        return parTitre.map { reference, siens in
            let recent = siens.max { $0.indexeLe < $1.indexeLe } ?? siens[0]
            return OeuvreTV(reference: reference, titre: recent.titre, cheminAffiche: recent.cheminAffiche, fichiers: siens.count,
                            qualite: recent.qualite, indexeLe: recent.indexeLe)
        }
        .sorted { ($0.indexeLe, $0.titre) > ($1.indexeLe, $1.titre) }
    }
}

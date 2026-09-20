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
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @Query private var chaines: [Chaine]

    @State private var duMoment: [ApercuTV] = []
    @State private var top: [ApercuTV] = []
    @State private var configuration = false
    /// Images de fond des titres de la soirée, lues sur TMDB quand le NAS ne les connaît pas.
    @State private var fonds: [ReferenceTitre: String] = [:]

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
                if let vedette { enTete(vedette) }
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
                if !teleCeSoir.isEmpty {
                    EtagereTV(titre: "Ce soir à la télé", sousTitre: "Films et séries de tes chaînes, à partir de maintenant") {
                        ForEach(teleCeSoir) { bloc in
                            let carte = CarteLargeTV(surtitre: bloc.debut <= .now ? "EN DIRECT" : bloc.debut.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH"))),
                                                     titre: bloc.premiere.titreGuide, detail: nomChaine(bloc.premiere.chaine),
                                                     cheminImage: bloc.premiere.cheminFond ?? bloc.premiere.cheminAffiche)
                            if let reference = bloc.reference {
                                NavigationLink(value: reference) { carte }.buttonStyle(.card)
                            } else {
                                Button {} label: { carte }.buttonStyle(.card)
                            }
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

    /// La grande image de tête : ta soirée si tu en as prévu une, sinon le titre du moment.
    private func enTete(_ vedette: Vedette) -> some View {
        NavigationLink(value: vedette.reference) {
            ImageTV(url: ImageTMDB.url(vedette.cheminImage, vedette.large ? .fondGrand : .afficheGrande), symboleVide: "")
                .frame(maxWidth: .infinity)
                .frame(height: 620)
                .overlay { LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom) }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(vedette.surtitre).font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.accentClair)
                        Text(vedette.titre).font(.system(size: 72, weight: .heavy)).lineLimit(2)
                        if let detail = vedette.detail { Text(detail).font(.system(size: 30)).foregroundStyle(.white.opacity(0.8)) }
                    }
                    .foregroundStyle(.white)
                    .padding(50)
                }
        }
        .buttonStyle(.card)
        .padding(.horizontal, MargesTV.bord)
        .focusSection()
    }

    private struct Vedette {
        let reference: ReferenceTitre
        let surtitre: String
        let titre: String
        let detail: String?
        let cheminImage: String?
        let large: Bool
    }

    private var vedette: Vedette? {
        if let prevu = ceSoir.first {
            let fond = fichiers.first { $0.reference == prevu.reference }?.cheminFond ?? fonds[prevu.reference]
            return Vedette(reference: prevu.reference, surtitre: ceSoir.count > 1 ? "CE SOIR · \(ceSoir.count) TITRES PRÉVUS" : "CE SOIR",
                           titre: prevu.titre, detail: surLeNAS(prevu.reference) ? "Sur ton NAS, prêt à lire" : nil,
                           cheminImage: fond ?? prevu.cheminAffiche, large: fond != nil)
        }
        guard let premier = duMoment.first else { return nil }
        return Vedette(reference: premier.reference, surtitre: "DU MOMENT", titre: premier.titre, detail: premier.sousTitre,
                       cheminImage: premier.cheminFond ?? premier.cheminAffiche, large: premier.cheminFond != nil)
    }

    /// Ce soir à la télé : en cours ou à venir dans la journée télé d'aujourd'hui.
    private var teleCeSoir: [BlocDiffusion] {
        let maintenant = Date.now
        let aujourdhui = GrilleTele.jourTele(maintenant)
        return GrilleTele.blocs(diffusions.filter { $0.fin > maintenant })
            .filter { GrilleTele.jourAffiche($0, maintenant: maintenant) == aujourdhui }
            .sorted { $0.debut < $1.debut }.prefix(12).map { $0 }
    }

    private func nomChaine(_ identifiant: String) -> String {
        NomChaineTV.lire(identifiant, parmi: chaines)
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
        // L'image de fond du premier titre de la soirée, pour la grande image de tête.
        if let prevu = ceSoir.first, fonds[prevu.reference] == nil, !surLeNAS(prevu.reference) {
            switch prevu.reference.type {
            case .film: fonds[prevu.reference] = (try? await client.film(prevu.reference.tmdbID, complements: []))?.cheminFond
            case .serie: fonds[prevu.reference] = (try? await client.serie(prevu.reference.tmdbID))?.cheminFond
            }
        }
    }
}

/// Un titre à montrer sur une étagère, film ou série.
struct ApercuTV: Identifiable, Hashable {
    let reference: ReferenceTitre
    let titre: String
    let sousTitre: String?
    let cheminAffiche: String?
    var cheminFond: String?
    let popularite: Double

    var id: ReferenceTitre { reference }

    /// `garderLOrdre` : celui de TMDB (une recherche, un tri choisi) plutôt que la popularité.
    static func meler(_ films: [FilmResume], _ series: [SerieResume], garderLOrdre: Bool = false) -> [ApercuTV] {
        let deFilms = films.map {
            ApercuTV(reference: ReferenceTitre(type: .film, tmdbID: $0.id), titre: $0.titre,
                     sousTitre: ["Film", $0.dateSortie.map { String($0.annee) }].compactMap { $0 }.joined(separator: " · "),
                     cheminAffiche: $0.cheminAffiche, cheminFond: $0.cheminFond, popularite: $0.popularite)
        }
        let deSeries = series.map {
            ApercuTV(reference: ReferenceTitre(type: .serie, tmdbID: $0.id), titre: $0.nom, sousTitre: "Série",
                     cheminAffiche: $0.cheminAffiche, cheminFond: $0.cheminFond, popularite: $0.popularite)
        }
        let tous = (deFilms + deSeries).filter { $0.cheminAffiche != nil }
        return (garderLOrdre ? tous : tous.sorted { $0.popularite > $1.popularite }).prefix(garderLOrdre ? 40 : 24).map { $0 }
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

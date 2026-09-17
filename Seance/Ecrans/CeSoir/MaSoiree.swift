import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce que la soirée propose sans rien chercher : épisodes à regarder et titres « à voir » disponibles.
@MainActor
@Observable
final class SoireeModele {
    struct Episode: Identifiable {
        var id: ReferenceTitre { serie.reference }
        let serie: SerieDetail
        let cheminAffiche: String?
        let numero: NumeroEpisode
    }

    struct Disponible: Identifiable {
        let id: ReferenceTitre
        let titre: String
        let cheminAffiche: String?
        let ou: String
    }

    private(set) var episodes: [Episode] = []
    private(set) var disponibles: [Disponible] = []
    /// « Sur Netflix », « Sur ton NAS » : pour les titres à voir et ceux gardés pour la soirée.
    private(set) var ou: [ReferenceTitre: String] = [:]
    private(set) var enCours = false

    /// Un titre qui arrive dans la soirée depuis les idées : son libellé est déjà connu.
    func noterOu(_ reference: ReferenceTitre, _ libelle: String?) {
        if let libelle { ou[reference] = libelle }
    }

    /// Séries en cours et titres « à voir » : quelques appels TMDB, six à la fois.
    func charger(etat: EtatApp, contexte: ModelContext) async {
        guard let tmdb = etat.tmdb, !enCours else { return }
        enCours = true
        defer { enCours = false }

        let suivis = (try? contexte.fetch(FetchDescriptor<Suivi>())) ?? []
        let series = suivis.filter { $0.type == .serie && $0.statut == .enCours }
        let aVoir = Array(suivis.filter { $0.statut == .aVoir }.prefix(24))
        let nas = Set(((try? contexte.fetch(FetchDescriptor<FichierNAS>(predicate: #Predicate { $0.tmdbID != nil }))) ?? []).compactMap(\.reference))
        let suivi = ServiceSuivi(contexte: contexte)

        let idsSeries = series.map(\.tmdbID)
        let jour = ServiceSoiree.soiree()
        let gardes = ((try? contexte.fetch(FetchDescriptor<SelectionSoir>())) ?? []).filter { $0.soiree == jour }.map(\.reference)
        let referencesOu = Array(Set(aVoir.map(\.reference) + gardes)).filter { !nas.contains($0) }
        async let fiches = Self.series(idsSeries, client: tmdb)
        async let offres = Self.offres(referencesOu, client: tmdb)

        episodes = await fiches.compactMap { serie in
            let vus = (try? suivi.episodesVus(serie.reference)) ?? []
            guard let prochain = ProgressionSerie.suivant(vus: vus, saisons: serie.saisons, dernierDiffuse: serie.dernierEpisode),
                  prochain.disponible else { return nil }
            return Episode(serie: serie, cheminAffiche: series.first { $0.tmdbID == serie.id }?.cheminAffiche ?? serie.cheminAffiche,
                           numero: prochain.numero)
        }

        // La même règle que « Regardable ce soir » dans Mes listes : NAS, abonnements, ou télé ce soir.
        let lesOffres = await offres
        let disponibilite = ServiceDisponibilite(contexte: contexte)
        let maintenant = Date.now
        var etats: [ReferenceTitre: EtatDisponibilite] = [:]
        for reference in Set(aVoir.map(\.reference) + gardes) {
            if let etatTitre = try? disponibilite.etat(reference, offres: lesOffres[reference]) { etats[reference] = etatTitre }
        }
        var libelles = ou
        for (reference, etatTitre) in etats {
            guard let libelle = RegardableCeSoir.libelle(etatTitre) else { continue }
            switch etatTitre {
            case .dansAbonnements: libelles[reference] = "Sur \(libelle)"
            case .aLaTeleBientot: libelles[reference] = "Ce soir sur \(libelle)"
            default: libelles[reference] = libelle
            }
        }
        ou = libelles
        disponibles = aVoir.compactMap { titre in
            guard let etatTitre = etats[titre.reference], RegardableCeSoir.retient(etatTitre, maintenant: maintenant),
                  let libelle = libelles[titre.reference] else { return nil }
            return Disponible(id: titre.reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, ou: libelle)
        }
    }

    /// Coche le prochain épisode : la fiche de sa saison donne sa durée.
    func marquerVu(_ episode: Episode, etat: EtatApp, contexte: ModelContext) async {
        guard let tmdb = etat.tmdb,
              let saison = try? await tmdb.saison(episode.numero.saison, serie: episode.serie.id),
              let detail = saison.episodes.first(where: { $0.numeroEpisode == episode.numero })
        else { return }
        _ = try? ServiceSuivi(contexte: contexte).cocher([detail], serie: episode.serie)
        await charger(etat: etat, contexte: contexte)
    }

    private static func series(_ ids: [Int], client: TMDBClient) async -> [SerieDetail] {
        await withTaskGroup(of: SerieDetail?.self) { groupe in
            for id in ids.prefix(24) {
                groupe.addTask { try? await client.serie(id) }
            }
            var resultat: [SerieDetail] = []
            for await serie in groupe {
                if let serie { resultat.append(serie) }
            }
            return resultat.sorted { $0.nom < $1.nom }
        }
    }

    private static func offres(_ references: [ReferenceTitre], client: TMDBClient) async -> [ReferenceTitre: OffresRegion] {
        await withTaskGroup(of: (ReferenceTitre, OffresRegion?).self) { groupe in
            for reference in references {
                groupe.addTask { (reference, try? await client.fournisseurs(reference.type, id: reference.tmdbID).offres()) }
            }
            var resultat: [ReferenceTitre: OffresRegion] = [:]
            for await (reference, offre) in groupe {
                resultat[reference] = offre
            }
            return resultat
        }
    }
}

/// Le haut de « Ce soir » : ma soirée, ce qu'il ne faut pas manquer, les épisodes et les titres disponibles.
struct SectionsSoiree: View {
    let modele: SoireeModele

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]
    @Query(sort: \Echeance.date) private var echeances: [Echeance]

    private var soiree: [SelectionSoir] {
        let jour = ServiceSoiree.soiree()
        return selections.filter { $0.soiree == jour }
    }

    private var retenus: Set<ReferenceTitre> {
        Set(soiree.map(\.reference))
    }

    /// Les rendez-vous de tes titres surveillés aujourd'hui : télé pas encore finie, épisodes et sorties du jour.
    /// Un titre déjà gardé pour la soirée n'y réapparaît pas.
    private var aNePasManquer: [Echeance] {
        let calendrier = Calendar.current
        let maintenant = Date.now
        let retenus = retenus
        var vus = Set<ReferenceTitre>()
        return echeances.filter { echeance in
            guard calendrier.isDateInToday(echeance.date), !retenus.contains(echeance.reference) else { return false }
            guard echeance.nature != .tele || echeance.date > maintenant.addingTimeInterval(-2 * 3600) else { return false }
            return vus.insert(echeance.reference).inserted
        }
    }

    /// Chaque titre n'apparaît qu'une fois dans « Ce soir » : ma soirée, puis à ne pas manquer, puis épisodes, puis ta liste.
    private var episodes: [SoireeModele.Episode] {
        let dejaMontres = retenus.union(aNePasManquer.map(\.reference))
        return modele.episodes.filter { !dejaMontres.contains($0.id) }
    }

    private var disponibles: [SoireeModele.Disponible] {
        let dejaMontres = retenus.union(aNePasManquer.map(\.reference)).union(episodes.map(\.id))
        return modele.disponibles.filter { !dejaMontres.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                entete("Ma soirée", symbole: "moon.stars.fill")
                if soiree.isEmpty {
                    MessageEtat(texte: "Rien de prévu pour l'instant. Touche 🌙 sur une fiche ou dans Mes listes pour garder un titre pour ce soir.",
                                symbole: "moon.stars")
                        .padding(.horizontal, -20)
                }
                ForEach(soiree) { selection in
                    ligne(reference: selection.reference, titre: selection.titre, affiche: selection.cheminAffiche,
                          detail: detail(selection.reference)) {
                        BoutonIcone(symbole: "xmark", libelle: "Retirer de ma soirée", taille: 34,
                                    explication: "Retirer ce titre de ta soirée. Il reste dans Mes listes.") {
                            try? ServiceSoiree(contexte: contexte).retirer(selection.reference)
                        }
                    }
                }
            }

            if !aNePasManquer.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    entete("À ne pas manquer ce soir", symbole: "bell.badge.fill")
                    ForEach(aNePasManquer) { echeance in
                        ligne(reference: echeance.reference, titre: echeance.titre, affiche: echeance.cheminAffiche, detail: echeance.libelle) {
                            boutonSoiree(echeance.reference, titre: echeance.titre, affiche: echeance.cheminAffiche)
                        }
                    }
                }
            }

            if !episodes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    entete("Épisodes à regarder", symbole: "play.tv.fill")
                    ForEach(episodes) { episode in
                        ligne(reference: episode.serie.reference, titre: episode.serie.nom, affiche: episode.cheminAffiche,
                              detail: "Épisode \(episode.numero)") {
                            HStack(spacing: 8) {
                                boutonSoiree(episode.serie.reference, titre: episode.serie.nom, affiche: episode.cheminAffiche)
                                BoutonIcone(symbole: "checkmark", libelle: "Marquer \(episode.numero) comme vu", principal: true, taille: 34,
                                            explication: "Marquer l'épisode \(episode.numero) comme vu : le suivant prendra sa place.") {
                                    Task { await modele.marquerVu(episode, etat: etat, contexte: contexte) }
                                }
                            }
                        }
                    }
                }
            }

            if !disponibles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    entete("Dans ta liste, regardable ce soir", symbole: "bookmark.fill")
                    ForEach(disponibles) { titre in
                        ligne(reference: titre.id, titre: titre.titre, affiche: titre.cheminAffiche, detail: titre.ou) {
                            boutonSoiree(titre.id, titre: titre.titre, affiche: titre.cheminAffiche)
                        }
                    }
                }
            }

            if modele.enCours, modele.episodes.isEmpty, modele.disponibles.isEmpty {
                MessageEtat(texte: "Recherche de tes épisodes et titres disponibles…", ton: .attente)
                    .padding(.horizontal, -20)
            }
        }
    }

    private func entete(_ titre: String, symbole: String) -> some View {
        Label(titre, systemImage: symbole)
            .font(.title3.weight(.bold))
            .labelStyle(EtiquetteSection())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// Ce que la soirée sait déjà d'un titre retenu : un rendez-vous du jour, un épisode, une plateforme.
    /// Les rendez-vous sont lus avant le retrait des doublons, qui écarte justement les titres de la soirée.
    private func detail(_ reference: ReferenceTitre) -> String {
        let calendrier = Calendar.current
        if let echeance = echeances.first(where: { $0.reference == reference && calendrier.isDateInToday($0.date) }) { return echeance.libelle }
        if let episode = modele.episodes.first(where: { $0.id == reference }) { return "Épisode \(episode.numero) à regarder" }
        if let disponible = modele.disponibles.first(where: { $0.id == reference }) { return disponible.ou }
        if let ou = modele.ou[reference] { return ou }
        return reference.type == .film ? "Film" : "Série"
    }

    @ViewBuilder
    private func boutonSoiree(_ reference: ReferenceTitre, titre: String, affiche: String?) -> some View {
        let retenu = retenus.contains(reference)
        BoutonIcone(symbole: retenu ? "moon.fill" : "moon", libelle: retenu ? "Retirer de ma soirée" : "Ajouter à ma soirée",
                    actif: retenu, taille: 34,
                    explication: retenu ? "Retirer ce titre de ta soirée." : "Ajouter ce titre à « Ma soirée », en haut de Ce soir.") {
            let service = ServiceSoiree(contexte: contexte)
            if retenu {
                try? service.retirer(reference)
            } else {
                try? service.retenir(reference, titre: titre, cheminAffiche: affiche)
            }
        }
    }

    private func ligne<Action: View>(
        reference: ReferenceTitre, titre: String, affiche: String?, detail: String, @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: reference) {
                HStack(spacing: 12) {
                    ImageDistante(url: ImageTMDB.url(affiche, .affiche), coins: 8)
                        .frame(width: 44, height: 66)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(titre).font(.headline).lineLimit(1)
                        Text(detail).font(.subheadline).foregroundStyle(Theme.accentClair).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            action()
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Titre de section avec une petite icône orange devant.
struct EtiquetteSection: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.subheadline).foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

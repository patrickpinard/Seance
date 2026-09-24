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
        /// Le nom et la durée de l'épisode, lus pour les séries de la soirée : « S01E01 · Winter Is Coming · 62 min ».
        var nom: String?
        var minutes: Int?

        /// « S01E01 · Winter Is Coming » ; le numéro seul tant que le nom n'est pas connu.
        var libelle: String {
            [numero.description, nom].compactMap { $0 }.joined(separator: " · ")
        }
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

        let jour = ServiceSoiree.soiree()
        let soirees = ((try? contexte.fetch(FetchDescriptor<SelectionSoir>())) ?? []).filter { $0.soiree >= jour }
        let gardes = soirees.filter { $0.soiree == jour }.map(\.reference)
        // Une série prévue pour une soirée compte même si elle n'a jamais été commencée : son prochain épisode est le
        // premier. Sans cela, la carte disait « Aucun nouvel épisode disponible » et n'offrait rien à cocher.
        let seriesPrevues = soirees.map(\.reference).filter { $0.type == .serie }
        let idsSeries = Array(Set(series.map(\.tmdbID) + seriesPrevues.map(\.tmdbID)))
        let referencesOu = Array(Set(aVoir.map(\.reference) + gardes)).filter { !nas.contains($0) }
        async let fiches = Self.series(idsSeries, client: tmdb)
        async let offres = Self.offres(referencesOu, client: tmdb)

        var prochains = await fiches.compactMap { serie -> Episode? in
            let vus = (try? suivi.episodesVus(serie.reference)) ?? []
            guard let prochain = ProgressionSerie.suivant(vus: vus, saisons: serie.saisons, dernierDiffuse: serie.dernierEpisode),
                  prochain.disponible else { return nil }
            return Episode(serie: serie, cheminAffiche: series.first { $0.tmdbID == serie.id }?.cheminAffiche ?? serie.cheminAffiche,
                           numero: prochain.numero)
        }
        // Le nom et la durée de l'épisode, pour les seules séries d'une soirée : une fiche de saison chacune.
        let prevues = Set(seriesPrevues)
        for (rang, episode) in prochains.enumerated() where prevues.contains(episode.id) {
            guard let saison = try? await tmdb.saison(episode.numero.saison, serie: episode.serie.id),
                  let detail = saison.episodes.first(where: { $0.numeroEpisode == episode.numero }) else { continue }
            prochains[rang].nom = detail.nom.isEmpty ? nil : detail.nom
            prochains[rang].minutes = detail.dureeMinutes ?? episode.serie.dureesEpisode.first
        }
        episodes = prochains

        // La même règle que « Regardable ce soir » dans Mes listes : NAS, abonnements, ou TV ce soir.
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

    /// Coche le prochain épisode : la fiche de sa saison donne sa durée. Rend l'épisode coché, pour « Vu avec qui ? ».
    @discardableResult
    func marquerVu(_ episode: Episode, etat: EtatApp, contexte: ModelContext) async -> EpisodeTMDB? {
        guard let tmdb = etat.tmdb,
              let saison = try? await tmdb.saison(episode.numero.saison, serie: episode.serie.id),
              let detail = saison.episodes.first(where: { $0.numeroEpisode == episode.numero })
        else { return nil }
        _ = try? ServiceSuivi(contexte: contexte).cocher([detail], serie: episode.serie)
        await charger(etat: etat, contexte: contexte)
        return detail
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

/// Ce qu'on peut ajouter à la soirée sans chercher : rendez-vous du jour, épisodes à regarder, titres de la liste
/// regardables ce soir. Un titre ajouté quitte ces listes : il est dans la soirée.
struct PropositionsSoiree: View {
    let modele: SoireeModele
    /// La soirée à remplir ; `nil` pour ce soir. Pour une soirée à venir, les rendez-vous d'aujourd'hui ne comptent pas.
    var soiree: String?

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]
    @Query(sort: \Echeance.date) private var echeances: [Echeance]

    private var retenus: Set<ReferenceTitre> {
        let jour = soiree ?? ServiceSoiree.soiree()
        return Set(selections.filter { $0.soiree == jour }.map(\.reference))
    }

    /// Les rendez-vous de tes titres surveillés aujourd'hui : TV pas encore finie, épisodes et sorties du jour.
    private var aNePasManquer: [Echeance] {
        guard soiree == nil else { return [] }
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

    /// Chaque titre n'apparaît qu'une fois : à ne pas manquer, puis épisodes, puis ta liste.
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
            if !aNePasManquer.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    entete("À ne pas manquer ce soir", symbole: "bell.badge.fill")
                    ForEach(aNePasManquer) { echeance in
                        ligne(reference: echeance.reference, titre: echeance.titre, affiche: echeance.cheminAffiche, detail: echeance.libelle)
                    }
                }
            }

            if !episodes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    entete("Épisodes à regarder", symbole: "play.tv.fill")
                    ForEach(episodes) { episode in
                        ligne(reference: episode.serie.reference, titre: episode.serie.nom, affiche: episode.cheminAffiche,
                              detail: "Épisode \(episode.numero)", episode: episode.numero)
                    }
                }
            }

            if !disponibles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    entete(soiree == nil ? "Dans ta liste, regardable ce soir" : "Dans ta liste, déjà regardable", symbole: "bookmark.fill")
                    ForEach(disponibles) { titre in
                        ligne(reference: titre.id, titre: titre.titre, affiche: titre.cheminAffiche, detail: titre.ou)
                    }
                }
            }

            if modele.enCours, episodes.isEmpty, disponibles.isEmpty {
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

    private func ligne(reference: ReferenceTitre, titre: String, affiche: String?, detail: String, episode: NumeroEpisode? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            enTeteLigne(reference: reference, titre: titre, affiche: affiche, detail: detail)
            // Où le regarder, tout de suite : lire sur le NAS, ouvrir la plateforme, ou la chaîne et l'heure.
            ActionsOuRegarder(reference: reference, titre: titre, episode: episode)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// La grande carte 16/9 de l'app, avec le bouton d'ajout posé dans son coin.
    private func enTeteLigne(reference: ReferenceTitre, titre: String, affiche: String?, detail: String) -> some View {
        NavigationLink(value: reference) {
            CarteLargeTitre(reference: reference, titre: titre, cheminAffiche: affiche, accroche: detail)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            BoutonIcone(symbole: "plus", libelle: soiree == nil ? "Ajouter à ma soirée" : "Prévoir pour cette soirée", principal: true, taille: 38,
                        explication: "Ajouter ce titre à la soirée choisie.") {
                try? ServiceSoiree(contexte: contexte).retenir(reference, titre: titre, cheminAffiche: affiche, soiree: soiree)
            }
            .padding(10)
        }
    }
}

/// Titre de section avec une petite icône orange devant.
struct EtiquetteSection: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.subheadline).foregroundStyle(Theme.texte2)
            configuration.title
        }
    }
}

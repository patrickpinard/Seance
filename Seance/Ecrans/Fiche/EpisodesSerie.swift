import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Suivi d'une série épisode par épisode (EF-11 à EF-13, EF-66) : prochain épisode à regarder,
/// progression, saisons avec cases à cocher, « vu jusqu'ici » et notes. Un épisode présent sur le NAS se lance d'ici (▶︎) :
/// c'est la seule liste d'épisodes de la fiche. « Déjà vu avant » coche une saison
/// ou toute la série sans la compter dans les statistiques.
struct SectionEpisodes: View {
    let serie: SerieDetail

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var visionnages: [Visionnage]
    /// Les épisodes de cette série présents sur le NAS : chacun se lance depuis sa ligne.
    @Query private var fichiersNAS: [FichierNAS]
    @State private var saisonChoisie: Int?
    @State private var saisonsChargees: [Int: SaisonDetail] = [:]
    @State private var erreur: String?

    init(serie: SerieDetail) {
        self.serie = serie
        let id = serie.id
        let type = TypeTitre.serie.rawValue
        _visionnages = Query(filter: #Predicate<Visionnage> { $0.tmdbID == id && $0.typeBrut == type })
        _fichiersNAS = Query(filter: #Predicate<FichierNAS> { $0.tmdbID == id && $0.typeBrut == type })
    }

    /// Le fichier du NAS d'un épisode ; la meilleure qualité quand il y en a plusieurs copies.
    private func fichierNAS(_ numero: NumeroEpisode) -> FichierNAS? {
        fichiersNAS.filter { $0.saison == numero.saison && $0.episode == numero.episode }
            .max { ($0.qualite.flatMap(QualiteVideo.init(description:)) ?? .sd) < ($1.qualite.flatMap(QualiteVideo.init(description:)) ?? .sd) }
    }

    private var saisonsSurNAS: Set<Int> {
        Set(fichiersNAS.compactMap(\.saison))
    }

    private var vus: Set<NumeroEpisode> {
        Set(visionnages.compactMap { v in
            guard let saison = v.saison, let episode = v.episode else { return nil }
            return NumeroEpisode(saison: saison, episode: episode)
        })
    }

    private var notes: [NumeroEpisode: Int] {
        Dictionary(visionnages.compactMap { v in
            guard let saison = v.saison, let episode = v.episode, let note = v.note else { return nil }
            return (NumeroEpisode(saison: saison, episode: episode), note)
        }, uniquingKeysWith: { premiere, _ in premiere })
    }

    private var saisons: [SaisonResume] {
        serie.saisons.filter { $0.numero > 0 && $0.nombreEpisodes > 0 }.sorted { $0.numero < $1.numero }
    }

    private var saisonAffichee: Int? {
        saisonChoisie ?? prochain?.numero.saison ?? saisons.first?.numero
    }

    private var prochain: (numero: NumeroEpisode, disponible: Bool)? {
        ProgressionSerie.suivant(vus: vus, saisons: serie.saisons, dernierDiffuse: serie.dernierEpisode)
    }

    var body: some View {
        if !saisons.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                TitreSection(titre: "Épisodes") {
                    Text("\(vus.count) \(vus.count > 1 ? "vus" : "vu") sur \(ProgressionSerie.total(serie.saisons))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(min(vus.count, ProgressionSerie.total(serie.saisons))),
                             total: Double(max(ProgressionSerie.total(serie.saisons), 1)))
                    .tint(Theme.accent)
                    .padding(.horizontal, 20)

                carteProchain

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(saisons) { saison in
                            let vusSaison = vus.filter { $0.saison == saison.numero }.count
                            PuceFiltre(
                                libelle: (vusSaison == saison.nombreEpisodes ? "✓ Saison \(saison.numero)" : "Saison \(saison.numero)")
                                    + (saisonsSurNAS.contains(saison.numero) ? " · NAS" : ""),
                                active: saison.numero == saisonAffichee
                            ) { saisonChoisie = saison.numero }
                            .accessibilityLabel("Saison \(saison.numero)\(saisonsSurNAS.contains(saison.numero) ? ", sur ton NAS" : "")")
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if let numero = saisonAffichee {
                    listeSaison(numero)
                }
                if let erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") {
                        if let numero = saisonAffichee { Task { await charger(numero) } }
                    }
                }
            }
            .task(id: saisonAffichee) {
                if let numero = saisonAffichee { await charger(numero) }
            }
        }
    }

    // MARK: Prochain épisode (EF-12)

    @ViewBuilder
    private var carteProchain: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let prochain {
                    let episode = saisonsChargees[prochain.numero.saison]?.episodes.first { $0.numeroEpisode == prochain.numero }
                    Text(prochain.disponible ? "À regarder" : "Prochain épisode")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(prochain.disponible ? Theme.accentClair : .secondary)
                    Text([prochain.numero.description, episode?.nom].compactMap { $0 }.joined(separator: " · "))
                        .font(.headline)
                        .lineLimit(2)
                    if !prochain.disponible {
                        Text(dateAnnoncee(prochain.numero).map { "Diffusé le \($0)" } ?? "Date de diffusion pas encore connue")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if ["Ended", "Canceled"].contains(serie.statut) {
                    Text("Série terminée").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text("Tu as tout vu").font(.headline)
                } else {
                    Text("À jour").font(.caption.weight(.bold)).foregroundStyle(Theme.texte2)
                    Text(serie.prochainEpisode?.dateDiffusion.map { "Prochain épisode le \(libelle($0))" } ?? "Nouveaux épisodes pas encore annoncés")
                        .font(.headline)
                }
            }
            Spacer()
            if let prochain, prochain.disponible, let fichier = fichierNAS(prochain.numero) {
                BoutonLectureNAS(fichier: fichier, libelle: "Lire \(prochain.numero) depuis le NAS")
            }
            if let prochain, prochain.disponible {
                BoutonIcone(symbole: "checkmark", libelle: "Marquer \(prochain.numero) comme vu", principal: true,
                            explication: "Marquer cet épisode comme vu. Appui long sur un épisode de la liste : « Vu jusqu'ici » ou une note.") {
                    Task { await marquer(jusqua: prochain.numero, seulement: true) }
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func dateAnnoncee(_ numero: NumeroEpisode) -> String? {
        if let episode = saisonsChargees[numero.saison]?.episodes.first(where: { $0.numeroEpisode == numero }), let date = episode.dateDiffusion {
            return libelle(date)
        }
        if let annonce = serie.prochainEpisode, annonce.numeroEpisode == numero, let date = annonce.dateDiffusion {
            return libelle(date)
        }
        return nil
    }

    // MARK: Saison

    @ViewBuilder
    private func listeSaison(_ numero: Int) -> some View {
        if let saison = saisonsChargees[numero] {
            let episodes = saison.episodes.sorted { $0.numero < $1.numero }
            let diffuses = episodes.filter(estDiffuse)
            let toutVu = !diffuses.isEmpty && diffuses.allSatisfy { vus.contains($0.numeroEpisode) }
            LazyVStack(spacing: 8) {
                ForEach(episodes) { episode in
                    ligne(episode)
                }
                if !diffuses.isEmpty {
                    Button(toutVu ? "Marquer la saison comme non vue" : "Marquer toute la saison comme vue") {
                        if toutVu {
                            for episode in diffuses { try? ServiceSuivi(contexte: contexte).decocher(episode.numeroEpisode, serie: serie.reference) }
                        } else {
                            _ = try? ServiceSuivi(contexte: contexte).cocher(diffuses, serie: serie)
                            replanifierAlertes()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.accent)
                    .padding(.top, 4)
                }
                boutonsDejaVu(saison: toutVu ? [] : diffuses)
            }
            .padding(.horizontal, 20)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding()
        }
    }

    /// Vu il y a longtemps : la saison affichée, ou toute la série jusqu'au dernier épisode diffusé.
    @ViewBuilder
    private func boutonsDejaVu(saison diffuses: [EpisodeTMDB]) -> some View {
        let resteSerie = prochain?.disponible == true
        if !diffuses.isEmpty || resteSerie {
            VStack(spacing: 6) {
                HStack(spacing: 16) {
                    if !diffuses.isEmpty {
                        Button("Saison déjà vue avant") {
                            _ = try? ServiceSuivi(contexte: contexte).cocher(diffuses, serie: serie, anterieur: true)
                            replanifierAlertes()
                        }
                    }
                    if resteSerie {
                        Button("Toute la série déjà vue avant") {
                            Task { await marquerToutDejaVu() }
                        }
                    }
                }
                .font(.subheadline)
                .tint(Theme.accentClair)
                Text("Déjà vu avant : la série sort des suggestions sans compter dans tes statistiques.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 2)
        }
    }

    private func ligne(_ episode: EpisodeTMDB) -> some View {
        let vu = vus.contains(episode.numeroEpisode)
        let diffuse = estDiffuse(episode)
        return HStack(spacing: 12) {
            ImageDistante(url: ImageTMDB.url(episode.cheminImage, .vignette), coins: 8)
                .frame(width: 104, height: 58)
                .opacity(diffuse ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(episode.numero). \(episode.nom)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text([episode.dateDiffusion.map(libelle) ?? "Date à venir", episode.dureeMinutes.map { "\($0) min" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    if let note = notes[episode.numeroEpisode] {
                        Label("\(note)/10", systemImage: "star.fill").foregroundStyle(Theme.accentClair)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let fichier = fichierNAS(episode.numeroEpisode) {
                    Label(["NAS", fichier.qualite].compactMap { $0 }.joined(separator: " · "), systemImage: "externaldrive.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .accessibilityLabel("Sur ton NAS")
                }
            }
            Spacer(minLength: 0)
            if let fichier = fichierNAS(episode.numeroEpisode) {
                BoutonLectureNAS(fichier: fichier, libelle: "Lire l'épisode \(episode.numero) depuis le NAS")
            }
            Button {
                if vu {
                    try? ServiceSuivi(contexte: contexte).decocher(episode.numeroEpisode, serie: serie.reference)
                } else {
                    _ = try? ServiceSuivi(contexte: contexte).cocher([episode], serie: serie)
                    replanifierAlertes()
                    quitterLaSoiree(apres: episode.numeroEpisode)
                }
            } label: {
                Image(systemName: vu ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(vu ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!diffuse && !vu)
            .accessibilityLabel(vu ? "Vu" : "Pas vu")
            .sensoryFeedback(.success, trigger: vu)
        }
        .padding(10)
        .background(Theme.surface.opacity(vu ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            if diffuse {
                Button("Vu jusqu'ici", systemImage: "checkmark.circle") {
                    Task { await marquer(jusqua: episode.numeroEpisode, seulement: false) }
                }
                Button("Déjà vu avant, jusqu'ici", systemImage: "clock.arrow.circlepath") {
                    Task { await marquer(jusqua: episode.numeroEpisode, seulement: false, anterieur: true) }
                }
            }
            if vu {
                Menu("Noter l'épisode", systemImage: "star") {
                    ForEach((1...10).reversed(), id: \.self) { note in
                        Button("\(note)/10") { try? ServiceSuivi(contexte: contexte).noter(episode.numeroEpisode, serie: serie.reference, note: note) }
                    }
                }
                Button("Marquer comme non vu", systemImage: "circle") {
                    try? ServiceSuivi(contexte: contexte).decocher(episode.numeroEpisode, serie: serie.reference)
                }
            }
        }
    }

    // MARK: Actions

    private func estDiffuse(_ episode: EpisodeTMDB) -> Bool {
        guard let date = episode.dateDiffusion else { return false }
        return date <= DateTMDB(.now)
    }

    private func libelle(_ date: DateTMDB) -> String {
        date.instant(heure: 12).formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_CH")))
    }

    private func charger(_ numero: Int) async {
        guard saisonsChargees[numero] == nil, let client = etat.tmdb else { return }
        do {
            saisonsChargees[numero] = try await client.saison(numero, serie: serie.id)
            erreur = nil
        } catch {
            self.erreur = "La saison \(numero) n'a pas pu être chargée."
            etat.journal.noter(.tmdb, "Les épisodes d'une saison n'ont pas pu être chargés.", erreur: error)
        }
    }

    /// Toute la série déjà vue avant : chaque saison est chargée, puis cochée jusqu'au dernier épisode diffusé.
    private func marquerToutDejaVu() async {
        guard let derniere = saisons.last else { return }
        await marquer(jusqua: NumeroEpisode(saison: derniere.numero, episode: derniere.nombreEpisodes), seulement: false, anterieur: true)
    }

    /// Coche un épisode, ou tous les épisodes diffusés jusqu'à lui en chargeant les saisons précédentes (EF-11).
    private func marquer(jusqua cible: NumeroEpisode, seulement: Bool, anterieur: Bool = false) async {
        let aCharger = seulement ? [cible.saison] : saisons.map(\.numero).filter { $0 <= cible.saison }
        for numero in aCharger { await charger(numero) }
        let connus = aCharger.compactMap { saisonsChargees[$0] }.flatMap(\.episodes)
        let episodes = seulement
            ? connus.filter { $0.numeroEpisode == cible }
            : ProgressionSerie.episodes(jusqua: cible, parmi: connus).filter(estDiffuse)
        guard !episodes.isEmpty else { return }
        _ = try? ServiceSuivi(contexte: contexte).cocher(episodes, serie: serie, anterieur: anterieur)
        replanifierAlertes()
        if seulement, !anterieur { quitterLaSoiree(apres: cible) }
    }

    /// Un épisode coché le soir où la série est prévue : c'était lui, la soirée. La série la quitte, comme depuis la page
    /// « Ce soir » ; « Encore un » la remet pour enchaîner sur le suivant.
    private func quitterLaSoiree(apres numero: NumeroEpisode) {
        let service = ServiceSoiree(contexte: contexte)
        guard (try? service.estRetenu(serie.reference)) == true else { return }
        try? service.retirer(serie.reference)
        let reference = serie.reference
        let nom = serie.nom
        let affiche = serie.cheminAffiche
        etat.confirmer("Épisode \(numero) vu · la série quitte ta soirée", symbole: "checkmark", libelleAction: "Encore un") { [contexte] in
            try? ServiceSoiree(contexte: contexte).retenir(reference, titre: nom, cheminAffiche: affiche)
        }
    }

    private func replanifierAlertes() {
        Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
    }
}

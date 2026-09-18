import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Mes listes (EF-16) : ce qui arrive pour les titres surveillés, puis à voir, en cours et terminés.
/// « Regardable ce soir » ne garde que ce qui est sur le NAS, dans les abonnements ou à la télé ce soir ;
/// la disponibilité et la durée sont lues sur TMDB seulement quand ce filtre ou le tri par durée le demande.
struct MesListesView: View {
    enum Onglet: String, CaseIterable, Identifiable {
        case aVenir = "À venir"
        case aVoir = "À voir"
        case enCours = "En cours"
        case termines = "Terminés"
        case listes = "Listes"

        var id: String { rawValue }

        var statut: StatutSuivi? {
            switch self {
            case .aVenir, .listes: nil
            case .aVoir: .aVoir
            case .enCours: .enCours
            case .termines: .termine
            }
        }
    }

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    @Query(sort: \Echeance.date) private var echeances: [Echeance]
    @Query private var visionnages: [Visionnage]
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]
    @State private var onglet = Onglet.aVoir
    @AppStorage("listes.tri") private var triBrut = TriListe.ajout.rawValue
    /// Affiches en grille, ou lignes détaillées : le même choix que dans Explorer.
    @AppStorage("listes.grille") private var enGrille = true
    @Environment(\.horizontalSizeClass) private var largeurGrille
    @State private var ceSoirSeulement = false
    /// Disponibilité et durée lues sur TMDB, par titre ; vidées quand les abonnements changent.
    @State private var infos: [ReferenceTitre: InfoTitre] = [:]
    @State private var chargementInfos = false
    @State private var confirmerToutSupprimer = false
    /// Recherche dans ses propres titres, sur l'onglet affiché.
    @State private var recherche = ""

    private struct InfoTitre {
        let etat: EtatDisponibilite
        let dureeMinutes: Int?
    }

    private struct CleInfos: Hashable {
        let references: [ReferenceTitre]
        let abonnements: [Int]
    }

    private var tri: TriListe {
        TriListe(rawValue: triBrut) ?? .ajout
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Liste", selection: $onglet) {
                    ForEach(Onglet.allCases) { onglet in
                        Text(onglet.rawValue).tag(onglet)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                if onglet == .aVenir {
                    aVenir
                } else if onglet == .listes {
                    SectionListesNommees(recherche: recherche)
                } else if let statut = onglet.statut {
                    barreListe(statut)
                    liste(statut)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle("Mes listes")
            .boutonBarreLaterale()
            .searchable(text: $recherche, prompt: "Chercher dans mes listes")
            .destinationsTitres()
            .navigationDestination(for: PersistentIdentifier.self) { id in
                ListePersoView(id: id)
            }
            .refreshable { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
            .task(id: cleInfos) { await chargerInfos(cleInfos.references) }
            // Le filtre ne survit pas à un changement d'écran : en revenant, toute la liste est là.
            .onDisappear { ceSoirSeulement = false }
            .onChange(of: abonnements.map(\.providerID)) { infos = [:] }
            .onChange(of: etat.listeDemandee, initial: true) { _, demande in
                guard let demande else { return }
                onglet = demande
                etat.listeDemandee = nil
            }
        }
    }

    // MARK: À venir

    @ViewBuilder
    private var aVenir: some View {
        // Un passage télé commencé depuis plus de trois heures est fini : il n'est plus « à venir ».
        let finTele = Date.now.addingTimeInterval(-3 * 3600)
        let futures = echeances.filter {
            $0.date >= Calendar.current.startOfDay(for: .now) && !($0.nature == .tele && $0.date < finTele)
                && (recherche.isEmpty || $0.titre.localizedCaseInsensitiveContains(recherche))
        }
        if suivis.contains(where: \.alertesActives) {
            BandeauAlertesCoupees()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        if futures.isEmpty {
            vide(etat.alertes.enCours
                 ? "Recherche des prochains épisodes et sorties…"
                 : "Rien d'annoncé pour l'instant. Touche la cloche 🔔 sur une fiche pour suivre ses prochains épisodes, ses sorties et ses passages à la télé.")
        } else {
            SectionAVenir(echeances: futures)
        }
    }

    private func compteARebours(_ date: Date) -> String {
        let jours = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch jours {
        case ..<1: return "Aujourd'hui"
        case 1: return "Demain"
        default: return "Dans \(jours) j"
        }
    }

    // MARK: À voir, en cours, terminés

    /// Filtre « Regardable ce soir » (pas pour les titres terminés) ou « Tout supprimer » (terminés), et ordre de la liste.
    private func barreListe(_ statut: StatutSuivi) -> some View {
        HStack(spacing: 10) {
            if statut != .termine {
                PuceFiltre(libelle: "Regardable ce soir", active: ceSoirSeulement) { ceSoirSeulement.toggle() }
                    .help("Sur le NAS, dans tes abonnements ou à la télé ce soir")
                // Le filtre cache des titres : c'est dit, pour ne pas les croire disparus.
                let masques = suivis.filter { $0.statut == statut && !$0.masque }.count - titresAffiches(statut).count
                if ceSoirSeulement, !chargementInfos, masques > 0 {
                    Text(Format.pluriel(masques, "masqué", "masqués"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !titresAffiches(.termine).isEmpty {
                // Action destructive rangée dans un menu : rouge seulement dans la confirmation.
                Menu {
                    Button(role: .destructive) { confirmerToutSupprimer = true } label: {
                        Label("Tout supprimer", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.accentClair)
                }
                .help("Supprimer tous les titres terminés de la liste")
                .confirmationDialog("Supprimer les \(titresAffiches(.termine).count) titres terminés ?",
                                    isPresented: $confirmerToutSupprimer, titleVisibility: .visible) {
                    Button("Tout supprimer", role: .destructive) {
                        let supprimes = titresAffiches(.termine)
                        try? ServiceSuivi(contexte: contexte).supprimerDesTermines(supprimes)
                        etat.confirmer("\(Format.pluriel(supprimes.count, "titre supprimé", "titres supprimés")) des terminés", symbole: "trash") { [contexte] in
                            supprimes.forEach { $0.masque = false }
                            try? contexte.save()
                        }
                    }
                } message: {
                    Text("Ils quittent la liste. Ce que tu as vu, tes notes et tes statistiques restent, et ils ne te seront pas reproposés.")
                }
            }
            if chargementInfos {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Menu {
                ForEach(TriListe.allCases, id: \.self) { choix in
                    Button { triBrut = choix.rawValue } label: {
                        if choix == tri {
                            Label(choix.rawValue, systemImage: "checkmark")
                        } else {
                            Text(choix.rawValue)
                        }
                    }
                }
            } label: {
                // Sur l'iPhone, le filtre, le tri et grille/liste partagent une ligne : le tri se réduit à son icône.
                if largeurGrille == .compact {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Label(tri.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .tint(Theme.accentClair)
            .accessibilityLabel("Trier : \(tri.rawValue)")
            Button { enGrille = true } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(enGrille ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Grille")
            .accessibilityAddTraits(enGrille ? .isSelected : [])
            Button { enGrille = false } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(enGrille ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Liste")
            .accessibilityAddTraits(enGrille ? [] : .isSelected)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
    }

    /// Le filtre ne s'applique pas aux terminés ; tant que la disponibilité d'un titre n'est pas connue, il est caché.
    private func titresAffiches(_ statut: StatutSuivi) -> [Suivi] {
        let tous = suivis.filter { $0.statut == statut && !$0.masque && (recherche.isEmpty || $0.titre.localizedCaseInsensitiveContains(recherche)) }
        let parReference = Dictionary(tous.map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
        let ordonnes = tri.trier(tous.map {
            TriListe.Element(reference: $0.reference, titre: $0.titre, ajouteLe: $0.ajouteLe, dureeMinutes: infos[$0.reference]?.dureeMinutes)
        }).compactMap { parReference[$0.reference] }
        guard ceSoirSeulement, statut != .termine else { return ordonnes }
        let maintenant = Date.now
        return ordonnes.filter { infos[$0.reference].map { RegardableCeSoir.retient($0.etat, maintenant: maintenant) } ?? false }
    }

    /// Les titres dont il faut la disponibilité ou la durée : seulement si le filtre ou le tri par durée le demande.
    private var cleInfos: CleInfos {
        guard let statut = onglet.statut, (ceSoirSeulement && statut != .termine) || tri == .plusCourt else {
            return CleInfos(references: [], abonnements: [])
        }
        return CleInfos(references: suivis.filter { $0.statut == statut }.map(\.reference),
                        abonnements: abonnements.map(\.providerID).sorted())
    }

    /// Une fiche TMDB par titre, six à la fois : plateformes et durée arrivent dans le même appel.
    private func chargerInfos(_ references: [ReferenceTitre]) async {
        let manquantes = references.filter { infos[$0] == nil }
        guard !manquantes.isEmpty, let client = etat.tmdb else { return }
        chargementInfos = true
        defer { chargementInfos = false }
        typealias Lu = (reference: ReferenceTitre, offres: OffresRegion?, duree: Int?)?
        await withTaskGroup(of: Lu.self) { groupe in
            var reste = manquantes[...]
            func lancer(_ reference: ReferenceTitre) {
                groupe.addTask {
                    switch reference.type {
                    case .film:
                        guard let film = try? await client.film(reference.tmdbID, complements: [.fournisseurs]) else { return nil }
                        return (reference, film.fournisseurs?.offres(), film.dureeMinutes)
                    case .serie:
                        guard let serie = try? await client.serie(reference.tmdbID, complements: [.fournisseurs]) else { return nil }
                        return (reference, serie.fournisseurs?.offres(), serie.dureesEpisode.first)
                    }
                }
            }
            for _ in 0..<6 {
                guard let reference = reste.popFirst() else { break }
                lancer(reference)
            }
            let disponibilite = ServiceDisponibilite(contexte: contexte)
            while let lu = await groupe.next() {
                if let lu, let etatTitre = try? disponibilite.etat(lu.reference, offres: lu.offres) {
                    infos[lu.reference] = InfoTitre(etat: etatTitre, dureeMinutes: lu.duree)
                }
                if Task.isCancelled { groupe.cancelAll(); return }
                if let suivante = reste.popFirst() { lancer(suivante) }
            }
        }
    }

    @ViewBuilder
    private func liste(_ statut: StatutSuivi) -> some View {
        let titres = titresAffiches(statut)
        if titres.isEmpty, ceSoirSeulement, statut != .termine, suivis.contains(where: { $0.statut == statut }) {
            vide(chargementInfos
                 ? "Recherche sur tes plateformes, ton NAS et la télé…"
                 : "Rien de regardable ce soir dans cette liste : ni sur tes plateformes, ni sur le NAS, ni à la télé.")
        } else if titres.isEmpty {
            switch statut {
            case .aVoir: vide("Rien à voir pour l'instant. Touche « + » sur une fiche pour l'ajouter ici.")
            case .enCours: vide("Aucune série en cours. Coche un épisode sur la fiche d'une série pour la suivre ici.")
            default: vide("Rien ici pour l'instant.")
            }
        }
        if enGrille, !titres.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: largeurGrille == .regular ? 150 : 105), spacing: 12, alignment: .top)], spacing: 18) {
                ForEach(titres) { suivi in
                    NavigationLink(value: suivi.reference) {
                        AfficheSuivi(suivi: suivi, rendezVous: prochainRendezVous(suivi), episodesVus: episodesVus(suivi))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(suivi, statut) }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            // La ligne contient des liens : sans cela, la liste lui dessine un chevron et lui prend sa largeur.
            .navigationLinkIndicatorVisibility(.hidden)
        }
        ForEach(enGrille ? [] : titres) { suivi in
            NavigationLink(value: suivi.reference) {
                ligne(suivi)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    try? ServiceSoiree(contexte: contexte).retenir(suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
                } label: { Label("Ce soir", systemImage: "moon.stars.fill") }
                    .tint(Theme.accent)
                if statut != .termine {
                    Button { changer(suivi, en: .termine) } label: { Label("Terminé", systemImage: "checkmark") }
                        .tint(.green)
                } else {
                    Button { changer(suivi, en: .aVoir) } label: { Label("À revoir", systemImage: "arrow.uturn.backward") }
                        .tint(.blue)
                }
            }
            .swipeActions(edge: .trailing) {
                if statut == .termine {
                    Button(role: .destructive) { supprimerDesTermines(suivi) } label: { Label("Supprimer", systemImage: "trash") }
                } else {
                    Button(role: .destructive) { retirer(suivi) } label: { Label("Retirer", systemImage: "trash") }
                }
                Button { basculerAlertes(suivi) } label: {
                    Label(suivi.alertesActives ? "Sans alertes" : "Alertes", systemImage: suivi.alertesActives ? "bell.slash" : "bell")
                }
                .tint(.orange)
            }
            // Clic droit sur le Mac, appui long sur l'iPhone : les mêmes actions que le glissement.
            .contextMenu { menu(suivi, statut) }
        }
    }

    /// Les actions d'un titre, les mêmes en liste et en grille.
    @ViewBuilder
    private func menu(_ suivi: Suivi, _ statut: StatutSuivi) -> some View {
        Button {
            try? ServiceSoiree(contexte: contexte).retenir(suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
        } label: { Label("Ajouter à ma soirée", systemImage: "moon.stars") }
        Button {
            etat.titreADater = TitreChoisi(reference: suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
        } label: { Label("Prévoir pour une soirée…", systemImage: "calendar") }
        Button {
            etat.titrePourListe = TitreChoisi(reference: suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
        } label: { Label("Ajouter à une liste…", systemImage: "list.bullet.rectangle.portrait") }
        if statut != .termine {
            Button { changer(suivi, en: .termine) } label: { Label("Terminé", systemImage: "checkmark") }
        } else {
            Button { changer(suivi, en: .aVoir) } label: { Label("À revoir", systemImage: "arrow.uturn.backward") }
        }
        if statut == .enCours {
            Button { changer(suivi, en: .aVoir) } label: { Label("Remettre à voir", systemImage: "bookmark") }
        }
        Button { basculerAlertes(suivi) } label: {
            Label(suivi.alertesActives ? "Sans alertes" : "Alertes", systemImage: suivi.alertesActives ? "bell.slash" : "bell")
        }
        Divider()
        if statut == .termine {
            Button(role: .destructive) { supprimerDesTermines(suivi) } label: { Label("Supprimer des terminés", systemImage: "trash") }
        } else {
            Button(role: .destructive) { retirer(suivi) } label: { Label("Retirer de mes listes", systemImage: "trash") }
        }
    }

    /// « S02E09 · dans 3 j » : le prochain rendez-vous d'un titre surveillé.
    private func prochainRendezVous(_ suivi: Suivi) -> String? {
        let aujourdhui = Calendar.current.startOfDay(for: .now)
        return echeances.first { $0.tmdbID == suivi.tmdbID && $0.typeBrut == suivi.typeBrut && $0.date >= aujourdhui }
            .map { "\($0.libelle) · \(compteARebours($0.date).lowercased())" }
    }

    private func episodesVus(_ suivi: Suivi) -> Int {
        guard suivi.type == .serie else { return 0 }
        return visionnages.filter { $0.tmdbID == suivi.tmdbID && $0.typeBrut == TypeTitre.serie.rawValue }.count
    }

    private func ligne(_ suivi: Suivi) -> some View {
        HStack(spacing: 12) {
            ImageDistante(url: ImageTMDB.url(suivi.cheminAffiche, .affiche), coins: 8)
                .frame(width: 50, height: 75)
            VStack(alignment: .leading, spacing: 4) {
                Text(suivi.titre).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    Text(suivi.type == .film ? "Film" : "Série")
                    if suivi.type == .serie {
                        let vus = visionnages.filter { $0.tmdbID == suivi.tmdbID && $0.typeBrut == TypeTitre.serie.rawValue }.count
                        if vus > 0 { Text("· \(vus) épisode\(vus > 1 ? "s" : "") vu\(vus > 1 ? "s" : "")") }
                    }
                    if let note = suivi.note {
                        Text("· ta note \(note)/10").foregroundStyle(Theme.accentClair)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let info = infos[suivi.reference], let disponible = RegardableCeSoir.libelle(info.etat) {
                    Label([disponible, info.dureeMinutes.map { suivi.type == .film ? Format.duree($0) : "\(Format.duree($0)) l'épisode" }]
                        .compactMap { $0 }.joined(separator: " · "), systemImage: symboleDisponibilite(info.etat))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RegardableCeSoir.retient(info.etat, maintenant: .now) ? Color.green : Color.secondary)
                }
                if let prochaine = echeances.first(where: { $0.tmdbID == suivi.tmdbID && $0.typeBrut == suivi.typeBrut && $0.date >= Calendar.current.startOfDay(for: .now) }) {
                    Label("\(prochaine.libelle) · \(compteARebours(prochaine.date).lowercased())", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentClair)
                }
            }
            Spacer(minLength: 0)
            if suivi.alertesActives {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Alertes activées")
            }
        }
    }

    private func symboleDisponibilite(_ etat: EtatDisponibilite) -> String {
        switch etat {
        case .surNAS: "externaldrive.fill"
        case .dansAbonnements: "play.tv"
        case .aLaTeleBientot: "tv"
        case .aLouerOuAcheter: "cart"
        case .introuvable: "questionmark.circle"
        }
    }

    private func vide(_ texte: String) -> some View {
        Text(texte)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
    }

    private func changer(_ suivi: Suivi, en statut: StatutSuivi) {
        let avant = suivi.statut
        suivi.statut = statut
        try? contexte.save()
        etat.confirmer(statut == .termine ? "« \(suivi.titre) » dans Terminés" : "« \(suivi.titre) » de nouveau à voir",
                       symbole: statut == .termine ? "checkmark" : "arrow.uturn.backward") { [contexte] in
            suivi.statut = avant
            try? contexte.save()
        }
    }

    private func retirer(_ suivi: Suivi) {
        let copie = InstantaneSuivi(suivi)
        contexte.delete(suivi)
        try? contexte.save()
        Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
        etat.confirmer("« \(copie.titre) » retiré de Mes listes", symbole: "trash") { [contexte, etat] in
            copie.restaurer(dans: contexte)
            Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
        }
    }

    /// Le titre quitte « Terminés » mais reste vu, noté et compté.
    private func supprimerDesTermines(_ suivi: Suivi) {
        try? ServiceSuivi(contexte: contexte).supprimerDesTermines([suivi])
        etat.confirmer("« \(suivi.titre) » supprimé des terminés", symbole: "trash") { [contexte] in
            suivi.masque = false
            try? contexte.save()
        }
    }

    private func basculerAlertes(_ suivi: Suivi) {
        suivi.alertesActives.toggle()
        try? contexte.save()
        Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
    }
}

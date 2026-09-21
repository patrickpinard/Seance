import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Une personne ouverte depuis un casting ou une recherche.
struct ReferencePersonne: Hashable {
    let id: Int
    let nom: String
}

/// Fiche acteur (EF-30 à EF-33) : portrait, biographie, « 12 films vus sur 38 », filmographie filtrable
/// avec vu / pas vu, et réalisations. Ouverte depuis les statistiques, elle montre d'abord les titres comptés.
/// La cloche suit l'acteur : un nouveau film où il joue déclenche une alerte.
struct PersonneView: View {
    let personne: ReferencePersonne
    let comptes: TitresAvecActeur?

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var visionnages: [Visionnage]
    /// Titres notés au premier lancement ou marqués terminés : vus aussi, sans visionnage daté.
    @Query(filter: #Predicate<Suivi> { $0.statutBrut == "termine" }) private var termines: [Suivi]
    @Query private var suiviActeur: [ActeurSuivi]
    @Query(filter: #Predicate<FichierNAS> { $0.tmdbID != nil }) private var fichiersNAS: [FichierNAS]
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]

    @State private var fiche: FichePersonne?
    @State private var filmographie: Filmographie?
    @State private var erreur: String?
    @State private var filtres = AnalyseFilmographie.Filtres()
    @State private var biographieComplete = false
    @State private var surMesPlateformes: Set<ReferenceTitre> = []
    @State private var plateformesChargees = false
    @AppStorage("personne.grille") private var enGrille = true
    @Environment(\.horizontalSizeClass) private var largeurGrille

    init(personne: ReferencePersonne, comptes: TitresAvecActeur? = nil) {
        self.personne = personne
        self.comptes = comptes
        let id = personne.id
        _suiviActeur = Query(filter: #Predicate<ActeurSuivi> { $0.personneID == id })
    }

    var body: some View {
        Group {
            if let filmographie {
                contenu(filmographie)
            } else if let erreur {
                ContentUnavailableView {
                    Label("Fiche indisponible", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(erreur)
                } actions: {
                    Button("Réessayer") { Task { await charger() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .background(Theme.fond)
        .navigationTitle(personne.nom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let suivi = !suiviActeur.isEmpty
                Button { basculerSuivi() } label: {
                    Label(suivi ? "Ne plus suivre" : "Suivre", systemImage: suivi ? "bell.fill" : "bell")
                }
                .help(suivi ? "Tu es prévenu quand un nouveau film avec \(personne.nom) est annoncé. Touche pour arrêter."
                            : "Être prévenu quand un nouveau film avec \(personne.nom) est annoncé")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    etat.filtreExplorerDemande = PersonneFiltre(id: personne.id, nom: personne.nom, cheminPortrait: fiche?.cheminPortrait,
                                                                estRealisateur: fiche?.domaine == "Directing")
                } label: {
                    Label("Dans Explorer", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("Ouvrir Explorer avec tous ses films, pour les filtrer par genre, période ou plateforme")
            }
        }
        .task(id: personne) { await charger() }
        .task(id: filtres.ceSoir) { if filtres.ceSoir { await chargerPlateformes() } }
    }

    // MARK: Contenu

    private func contenu(_ filmographie: Filmographie) -> some View {
        let aujourdhui = DateTMDB(.now)
        let credits = AnalyseFilmographie.filtrer(filmographie.roles, filtres: filtres, vus: vus, regardables: regardables)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                enTete
                biographie

                HStack(spacing: 12) {
                    compteur(AnalyseFilmographie.compte(filmographie.roles, type: .film, vus: vus, aujourdhui: aujourdhui), singulier: "film vu", pluriel: "films vus")
                    compteur(AnalyseFilmographie.compte(filmographie.roles, type: .serie, vus: vus, aujourdhui: aujourdhui), singulier: "série vue", pluriel: "séries vues")
                }
                .padding(.horizontal, 20)

                if let comptes {
                    sectionComptes(comptes, filmographie: filmographie)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SelecteurCases(selection: $filtres.type, cases: [.init(valeur: TypeTitre.film, nom: "Films"), .init(valeur: TypeTitre.serie, nom: "Séries")])
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            PuceFiltre(libelle: "Action", active: filtres.actionSeulement) { filtres.actionSeulement.toggle() }
                            PuceFiltre(libelle: "Pas vus", active: filtres.pasVus) { filtres.pasVus.toggle() }
                            PuceFiltre(libelle: "Regardables ce soir", active: filtres.ceSoir) { filtres.ceSoir.toggle() }
                        }
                        .padding(.horizontal, 20)
                    }

                    if filtres.ceSoir, !plateformesChargees {
                        MessageEtat(texte: "Recherche sur tes plateformes, ton NAS et la TV…", ton: .attente)
                    } else if credits.isEmpty {
                        MessageEtat(texte: "Aucun titre ne correspond à ces filtres.", symbole: "line.3.horizontal.decrease")
                    }
                    grilleOuListe(credits, choix: true)
                }

                let realisations = AnalyseFilmographie.significatifs(filmographie.realisations)
                if !realisations.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection("Réalisations")
                        grilleOuListe(realisations, choix: false)
                    }
                }

                Text("Filmographie : TMDB")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
        }
    }

    private var enTete: some View {
        HStack(spacing: 16) {
            ImageDistante(url: ImageTMDB.url(fiche?.cheminPortrait, .portrait), coins: 55, symboleVide: "person.fill")
                .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 6) {
                Text(fiche?.nom ?? personne.nom).font(.title2.weight(.heavy)).lineLimit(2)
                if let domaine = fiche?.domaine {
                    Text(domaine == "Directing" ? "Réalisation" : domaine == "Acting" ? "Interprétation" : domaine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentClair)
                }
                let details = [fiche?.age(aujourdhui: DateTMDB(.now)).map { fiche?.dateDeces == nil ? "\($0) ans" : "Décédé à \($0) ans" },
                               fiche?.lieuNaissance].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var biographie: some View {
        if let texte = fiche?.biographie, !texte.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(texte)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(biographieComplete ? nil : 4)
                Button(biographieComplete ? "Réduire" : "Lire la suite") { biographieComplete.toggle() }
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.accent)
            }
            .padding(.horizontal, 20)
        }
    }

    /// Les titres que les statistiques ont comptés pour cet acteur, dans le même ordre : le chiffre et la liste
    /// ne peuvent pas diverger. Un titre absent de sa filmographie TMDB est signalé plutôt que caché.
    private func sectionComptes(_ comptes: TitresAvecActeur, filmographie: Filmographie) -> some View {
        let credits = Dictionary((filmographie.roles + filmographie.realisations).map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
        return VStack(alignment: .leading, spacing: 12) {
            TitreSection(titre: "Dans tes statistiques") {
                Text("\(Format.pluriel(comptes.titres.count, "titre")) \(comptes.periode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 10) {
                ForEach(comptes.titres, id: \.self) { reference in
                    if let credit = credits[reference] {
                        ligne(credit)
                    } else {
                        ligneHorsFilmographie(reference)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func ligneHorsFilmographie(_ reference: ReferenceTitre) -> some View {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        let suivi = try? contexte.fetch(FetchDescriptor<Suivi>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type })).first
        return NavigationLink(value: reference) {
            HStack(spacing: 12) {
                ImageDistante(url: ImageTMDB.url(suivi?.cheminAffiche, .affiche), coins: 8)
                    .frame(width: 50, height: 75)
                VStack(alignment: .leading, spacing: 4) {
                    Text(suivi?.titre ?? "Titre \(id)").font(.headline).lineLimit(2)
                    Label("Absent de sa filmographie TMDB", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func compteur(_ compte: AnalyseFilmographie.Compte, singulier: String, pluriel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(compte.vus)").font(.title.weight(.heavy))
                Text("sur \(compte.total)").font(.subheadline).foregroundStyle(.secondary)
            }
            // « 1 sur 88 films vus » : l'accord suit le total.
            Text(compte.total > 1 ? pluriel : singulier)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(compte.vus), total: Double(max(compte.total, 1)))
                .tint(Theme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// La filmographie en affiches, comme Mes listes et Explorer ; ou en lignes, qui disent le rôle.
    @ViewBuilder
    private func grilleOuListe(_ credits: [CreditPersonne], choix: Bool) -> some View {
        if choix, !credits.isEmpty {
            HStack(spacing: 12) {
                Text(Format.pluriel(credits.count, "titre")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                BasculeGrilleListe(enGrille: $enGrille)
            }
            .font(.title3)
            .padding(.horizontal, 20)
        }
        if enGrille {
            LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
                ForEach(credits, id: \.reference) { credit in
                    NavigationLink(value: credit.reference) {
                        CarteLargeTitre(credit.titreResume, accroche: vus.contains(credit.reference) ? "✓ Vu" : nil)
                    }
                    .buttonStyle(.plain)
                    .actionsRapides(credit.titreResume)
                }
            }
            .padding(.horizontal, 20)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(credits, id: \.reference) { credit in
                    ligne(credit)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func ligne(_ credit: CreditPersonne) -> some View {
        let vu = vus.contains(credit.reference)
        return NavigationLink(value: credit.reference) {
            HStack(spacing: 12) {
                ImageDistante(url: ImageTMDB.url(credit.cheminAffiche, .affiche), coins: 8)
                    .frame(width: 50, height: 75)
                VStack(alignment: .leading, spacing: 4) {
                    Text(credit.titre).font(.headline).lineLimit(2)
                    Text([credit.date.map { String($0.annee) } ?? "À venir", credit.personnage.flatMap { $0.isEmpty ? nil : $0 }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Label(vu ? "Vu" : "Pas vu", systemImage: vu ? "checkmark.circle.fill" : "circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(vu ? Color.green : Color.secondary)
                        if referencesNAS.contains(credit.reference) {
                            Label("NAS", systemImage: "externaldrive.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accentClair)
                        }
                        if surMesPlateformes.contains(credit.reference) {
                            Label("Abonnement", systemImage: "play.tv")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accentClair)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let note = credit.noteMoyenne, (credit.nombreVotes ?? 0) > 0 {
                    AnneauNote(pourcentage: Int((note * 10).rounded()), diametre: 34)
                }
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .actionsRapides(credit.titreResume)
    }

    // MARK: Données

    /// Films vus, séries dont au moins un épisode a été vu, et titres notés comme déjà vus :
    /// la même règle que les suggestions.
    private var vus: Set<ReferenceTitre> {
        Set(visionnages.map { ReferenceTitre(type: $0.type, tmdbID: $0.tmdbID) }).union(termines.map(\.reference))
    }

    private func basculerSuivi() {
        let service = ServiceActeurs(contexte: contexte)
        if suiviActeur.isEmpty {
            try? service.suivre(personneID: personne.id, nom: fiche?.nom ?? personne.nom, cheminPortrait: fiche?.cheminPortrait)
            // La première lecture mémorise sa filmographie : seuls les films annoncés ensuite déclencheront une alerte.
            Task {
                await etat.alertes.demanderAutorisation()
                await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb)
            }
        } else {
            try? service.nePlusSuivre(personne.id)
        }
    }

    private var referencesNAS: Set<ReferenceTitre> {
        Set(fichiersNAS.compactMap(\.reference))
    }

    /// NAS, abonnements (chargés à la demande) et TV des prochaines heures.
    private var regardables: Set<ReferenceTitre> {
        let maintenant = Date.now
        let finDeSoiree = Calendar.current.startOfDay(for: maintenant).addingTimeInterval(26 * 3600)
        let diffusions = (try? contexte.fetch(FetchDescriptor<Diffusion>(predicate: #Predicate { $0.fin > maintenant && $0.debut < finDeSoiree }))) ?? []
        let tele = diffusions.compactMap { d in d.tmdbID.map { ReferenceTitre(type: TypeTitre(rawValue: d.typeBrut) ?? .film, tmdbID: $0) } }
        return referencesNAS.union(tele).union(surMesPlateformes)
    }

    private func charger() async {
        guard let client = etat.tmdb else {
            erreur = "Enregistre d'abord ta clé TMDB dans Réglages › TMDB."
            return
        }
        erreur = nil
        async let personneChargee = client.personne(personne.id)
        async let credits = client.filmographie(personne: personne.id)
        do {
            filmographie = try await credits
            fiche = try? await personneChargee
        } catch is CancellationError {
            return
        } catch {
            erreur = Journal.conseil(error) ?? "TMDB ne répond pas pour l'instant."
            etat.journal.noter(.tmdb, "Une fiche acteur n'a pas pu être chargée.", erreur: error)
        }
    }

    /// Disponibilité sur les plateformes cochées, pour le filtre « Regardables ce soir ».
    private func chargerPlateformes() async {
        guard !plateformesChargees, let client = etat.tmdb, let filmographie else { return }
        let ids = Set(abonnements.map(\.providerID))
        let references = AnalyseFilmographie.significatifs(filmographie.roles + filmographie.realisations)
            .filter { $0.date.map { $0 <= DateTMDB(.now) } ?? false }
            .map(\.reference)
        let trouves = await withTaskGroup(of: ReferenceTitre?.self) { groupe in
            var reste = Array(references.prefix(80))[...]
            func lancer(_ reference: ReferenceTitre) {
                groupe.addTask {
                    guard let offres = try? await client.fournisseurs(reference.type, id: reference.tmdbID).offres() else { return nil }
                    let inclus = (offres.abonnement + offres.gratuit + offres.avecPublicite).contains { ids.contains($0.id) }
                    return inclus ? reference : nil
                }
            }
            for _ in 0..<6 {
                guard let reference = reste.popFirst() else { break }
                lancer(reference)
            }
            var resultat = Set<ReferenceTitre>()
            while let trouve = await groupe.next() {
                if let trouve { resultat.insert(trouve) }
                if let suivante = reste.popFirst() { lancer(suivante) }
            }
            return resultat
        }
        surMesPlateformes = trouves
        plateformesChargees = true
    }
}

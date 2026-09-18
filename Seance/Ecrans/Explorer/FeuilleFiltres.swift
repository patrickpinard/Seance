import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Libellés des critères actifs, pour les puces au-dessus des résultats (EF-54).
enum LibellesFiltres {
    static let langues: [(code: String, nom: String)] = [
        (FiltresExplorer.francaisOuAnglais, "Français ou anglais"),
        ("fr", "Français"), ("en", "Anglais"), ("ko", "Coréen"), ("ja", "Japonais"), ("es", "Espagnol"), ("it", "Italien"),
    ]

    static func libelle(_ critere: FiltresExplorer.Critere, _ f: FiltresExplorer, genres: [Genre]) -> (texte: String, portrait: URL?) {
        func nomGenre(_ id: Int) -> String { genres.first { $0.id == id }?.nom ?? "Genre \(id)" }
        switch critere {
        case .personne(let id):
            let personne = f.personnes.first { $0.id == id }
            return (personne?.nom ?? "Personne", ImageTMDB.url(personne?.cheminPortrait, .portrait))
        case .genre(let id): return (nomGenre(id), nil)
        case .genreExclu(let id): return ("Sans \(nomGenre(id).lowercased())", nil)
        case .sousGenre(let id): return (SousGenre.catalogue.first { $0.id == id }?.nom ?? id, nil)
        case .periode:
            switch (f.anneeDebut, f.anneeFin) {
            case let (debut?, fin?) where debut == fin: return (String(debut), nil)
            case let (debut?, fin?): return ("\(debut) – \(fin)", nil)
            case let (debut?, nil): return ("Depuis \(debut)", nil)
            case let (nil, fin?): return ("Jusqu'en \(fin)", nil)
            default: return ("Période", nil)
            }
        case .typesSortie: return (f.typesSortie.map(nom).joined(separator: ", "), nil)
        case .note: return ("Note ≥ \((f.noteMin ?? 0).formatted(.number.precision(.fractionLength(0...1))))", nil)
        case .votes: return ("≥ \((f.votesMin ?? 0).formatted()) votes", nil)
        case .duree: return ("≤ \(duree(f.dureeMax ?? 0))", nil)
        case .langue: return (langues.first { $0.code == f.langue }?.nom ?? f.langue ?? "", nil)
        case .plateformes: return ("Mes plateformes", nil)
        case .monetisation: return (f.monetisations.map(nom).joined(separator: ", "), nil)
        case .obtention: return (nom(f.locaux.obtention), nil)
        case .tele: return (f.locaux.tele == .ceSoir ? "À la télé ce soir" : "À la télé cette semaine", nil)
        case .dejaVu: return (f.locaux.dejaVu == .vus ? "Déjà vus" : "Pas encore vus", nil)
        }
    }

    static func nom(_ type: TypeSortie) -> String {
        switch type {
        case .avantPremiere: "Avant-première"
        case .sallesLimitees: "Salles (limitée)"
        case .salles: "Salles"
        case .numerique: "Numérique"
        case .physique: "DVD, Blu-ray"
        case .television: "Télévision"
        }
    }

    static func nom(_ monetisation: CriteresDecouverte.Monetisation) -> String {
        switch monetisation {
        case .abonnement: "Abonnement"
        case .gratuit: "Gratuit"
        case .avecPublicite: "Avec pub"
        case .location: "Location"
        case .achat: "Achat"
        }
    }

    static func nom(_ obtention: CritereObtention) -> String {
        switch obtention {
        case .tous: "Peu importe"
        case .surNAS: "Sur le NAS"
        case .pasSurNAS: "Pas sur le NAS"
        case .nasOuAbonnements: "NAS ou abonnements"
        case .aObtenir: "À obtenir"
        }
    }

    static func nom(_ tri: CriteresDecouverte.Tri) -> String {
        switch tri {
        case .popularite: "popularité"
        case .note: "note"
        case .date: "date"
        case .titre: "titre"
        case .votes: "nombre de votes"
        }
    }

    static func duree(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }
}

/// Feuille « Filtres » de la maquette (EF-53, EF-55, EF-57) : le brouillon ne s'applique qu'avec
/// « Voir N films » ; le nombre se met à jour pendant le réglage.
struct FeuilleFiltres: View {
    let depart: FiltresExplorer
    let modele: ExplorerModele
    let appliquer: (FiltresExplorer) -> Void

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]

    @State private var brouillon = FiltresExplorer()
    @State private var nombre: Int?
    @State private var comptageEnCours = false
    @State private var recherchePersonne = ""
    @State private var personnesTrouvees: [PersonneResume] = []
    @State private var nomEnregistrement = ""
    @State private var enregistrementOuvert = false

    private let anneeCourante = Calendar.current.component(.year, from: .now)
    private var bornes: ClosedRange<Int> { 1950...anneeCourante }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    periode
                    separateur
                    genres
                    separateur
                    sousGenres
                    separateur
                    personnes
                    separateur
                    noteEtVotes
                    separateur
                    dureeEtLangue
                    separateur
                    disponibilite
                    separateur
                    surIPhone
                    separateur
                    tri
                }
                .padding(20)
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.fond)
            .titreDeFeuille("Filtres")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Réinitialiser") { brouillon = FiltresExplorer(type: brouillon.type) }
                        .tint(Theme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { enregistrementOuvert = true }
                        .disabled(brouillon.criteresActifs.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) { boutonVoir }
            .alert("Enregistrer ces filtres", isPresented: $enregistrementOuvert) {
                TextField("Keanu, années 2010, sur mes plateformes", text: $nomEnregistrement)
                Button("Enregistrer") { enregistrer() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ils se rappellent d'un geste, au-dessus des résultats d'Explorer.")
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.fond)
        .onAppear { brouillon = depart }
        .task(id: brouillon) { await compter() }
        .task(id: recherchePersonne) { await chercherPersonnes() }
    }

    private var separateur: some View {
        Divider().overlay(Theme.trait)
    }

    private func entete(_ titre: String, _ detail: String? = nil, accent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titre).font(.headline)
            Spacer()
            if let detail {
                Text(detail)
                    .font(accent ? .headline : .footnote)
                    .foregroundStyle(accent ? AnyShapeStyle(Theme.accentClair) : AnyShapeStyle(.secondary))
            }
        }
    }

    // MARK: Sections

    private var periode: some View {
        VStack(alignment: .leading, spacing: 14) {
            entete("Période de sortie", brouillon.anneeDebut == nil && brouillon.anneeFin == nil
                   ? "Toutes" : "\(brouillon.anneeDebut ?? bornes.lowerBound) – \(brouillon.anneeFin ?? anneeCourante)", accent: true)
            CurseurIntervalle(
                debut: Binding { brouillon.anneeDebut ?? bornes.lowerBound } set: { brouillon.anneeDebut = $0 == bornes.lowerBound ? nil : $0 },
                fin: Binding { brouillon.anneeFin ?? anneeCourante } set: { brouillon.anneeFin = $0 == anneeCourante ? nil : $0 },
                bornes: bornes
            )
            HStack {
                Text(String(bornes.lowerBound))
                Spacer()
                Text("1990")
                Spacer()
                Text("2010")
                Spacer()
                Text(String(anneeCourante))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Flux {
                ForEach(RaccourciPeriode.catalogue(anneeCourante: anneeCourante)) { raccourci in
                    let actif = brouillon.anneeDebut == raccourci.debut && brouillon.anneeFin == raccourci.fin
                    PuceCritere(libelle: raccourci.nom, etat: actif ? .retenu : .neutre) {
                        if actif {
                            brouillon.retirer(.periode)
                        } else {
                            brouillon.anneeDebut = raccourci.debut
                            brouillon.anneeFin = raccourci.fin
                        }
                    }
                }
            }
        }
    }

    private var genres: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete("Genres", "Appui long pour exclure")
            let liste = etat.genres[brouillon.type] ?? []
            if liste.isEmpty {
                ProgressView()
            }
            Flux {
                ForEach(liste) { genre in
                    PuceCritere(
                        libelle: genre.nom,
                        etat: brouillon.genresInclus.contains(genre.id) ? .retenu : brouillon.genresExclus.contains(genre.id) ? .exclu : .neutre,
                        action: { brouillon.basculer(genre: genre.id) },
                        appuiLong: { brouillon.exclure(genre: genre.id) }
                    )
                }
            }
        }
    }

    private var sousGenres: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete("Sous-genres")
            Flux {
                ForEach(SousGenre.catalogue) { sousGenre in
                    let actif = brouillon.sousGenres.contains(sousGenre.id)
                    PuceCritere(libelle: sousGenre.nom, etat: actif ? .retenu : .neutre) {
                        if actif { brouillon.retirer(.sousGenre(sousGenre.id)) } else { brouillon.sousGenres.append(sousGenre.id) }
                    }
                }
            }
        }
    }

    private var personnes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Acteurs et réalisateurs").font(.headline)
                Spacer()
                if brouillon.personnes.count > 1 {
                    Picker("Combinaison", selection: $brouillon.personnesEnsemble) {
                        Text("Tous ensemble").tag(true)
                        Text("Au moins un").tag(false)
                    }
                    .pickerStyle(.menu)
                    .tint(.secondary)
                }
            }
            if !brouillon.personnes.isEmpty {
                Flux {
                    ForEach(brouillon.personnes) { personne in
                        PuceActive(libelle: personne.nom, portrait: ImageTMDB.url(personne.cheminPortrait, .portrait)) {
                            brouillon.retirer(.personne(personne.id))
                        }
                    }
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Ajouter un acteur ou un réalisateur", text: $recherchePersonne)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            ForEach(personnesTrouvees) { personne in
                Button {
                    brouillon.personnes.append(PersonneFiltre(
                        id: personne.id, nom: personne.nom, cheminPortrait: personne.cheminPortrait,
                        estRealisateur: personne.domaine == "Directing"
                    ))
                    recherchePersonne = ""
                    personnesTrouvees = []
                } label: {
                    HStack(spacing: 10) {
                        ImageDistante(url: ImageTMDB.url(personne.cheminPortrait, .portrait), coins: 18, symboleVide: "person.fill")
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading) {
                            Text(personne.nom).font(.subheadline.weight(.semibold))
                            Text(personne.domaine == "Directing" ? "Réalisation" : "Interprétation")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
                .buttonStyle(.plain)
            }
            if brouillon.type == .serie, !brouillon.personnes.isEmpty {
                Text("Pour les séries, Séance parcourt la filmographie de chaque personne.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var noteEtVotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete("Note TMDB minimale", brouillon.noteMin.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) et plus" } ?? "Toutes",
                   accent: brouillon.noteMin != nil)
            Slider(value: Binding { brouillon.noteMin ?? 0 } set: { brouillon.noteMin = $0 < 0.5 ? nil : $0 }, in: 0...9.5, step: 0.5)
                .tint(Theme.accent)
            Text("Votes minimum").font(.subheadline.weight(.semibold)).padding(.top, 4)
            Flux {
                ForEach([0, 100, 500, 1000, 5000], id: \.self) { votes in
                    let actif = (brouillon.votesMin ?? 0) == votes
                    PuceCritere(libelle: votes == 0 ? "Tous" : votes.formatted(), etat: actif ? .retenu : .neutre) {
                        brouillon.votesMin = votes == 0 ? nil : votes
                    }
                }
            }
        }
    }

    private var dureeEtLangue: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete(brouillon.type == .film ? "Durée maximale" : "Durée d'un épisode")
            Flux {
                ForEach(brouillon.type == .film ? [0, 90, 120, 150] : [0, 30, 45, 60], id: \.self) { minutes in
                    let actif = (brouillon.dureeMax ?? 0) == minutes
                    PuceCritere(libelle: minutes == 0 ? "Peu importe" : "≤ \(LibellesFiltres.duree(minutes))", etat: actif ? .retenu : .neutre) {
                        brouillon.dureeMax = minutes == 0 ? nil : minutes
                    }
                }
            }
            Text("Langue originale").font(.subheadline.weight(.semibold)).padding(.top, 4)
            Flux {
                PuceCritere(libelle: "Toutes", etat: brouillon.langue == nil ? .retenu : .neutre) { brouillon.langue = nil }
                ForEach(LibellesFiltres.langues, id: \.code) { langue in
                    PuceCritere(libelle: langue.nom, etat: brouillon.langue == langue.code ? .retenu : .neutre) {
                        brouillon.langue = brouillon.langue == langue.code ? nil : langue.code
                    }
                }
            }
            if brouillon.type == .film {
                Text("Type de sortie").font(.subheadline.weight(.semibold)).padding(.top, 4)
                Flux {
                    ForEach([TypeSortie.salles, .numerique, .physique, .television], id: \.self) { type in
                        let actif = brouillon.typesSortie.contains(type)
                        PuceCritere(libelle: LibellesFiltres.nom(type), etat: actif ? .retenu : .neutre) {
                            if actif { brouillon.typesSortie.removeAll { $0 == type } } else { brouillon.typesSortie.append(type) }
                        }
                    }
                }
            }
        }
    }

    private var disponibilite: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete("Disponibilité en Suisse")
            Toggle("Sur mes plateformes", isOn: $brouillon.mesPlateformes)
                .tint(Theme.accent)
                .disabled(abonnements.isEmpty)
            if abonnements.isEmpty {
                Text("Coche tes abonnements dans Réglages › Plateformes.").font(.caption).foregroundStyle(.secondary)
            }
            Flux {
                ForEach([CriteresDecouverte.Monetisation.abonnement, .gratuit, .location, .achat], id: \.self) { monetisation in
                    let actif = brouillon.monetisations.contains(monetisation)
                    PuceCritere(libelle: LibellesFiltres.nom(monetisation), etat: actif ? .retenu : .neutre) {
                        if actif { brouillon.monetisations.removeAll { $0 == monetisation } } else { brouillon.monetisations.append(monetisation) }
                    }
                }
            }
        }
    }

    private var surIPhone: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete("NAS, télé et historique", "filtrés par l'app")
            Flux {
                ForEach([CritereObtention.tous, .surNAS, .pasSurNAS, .aObtenir], id: \.self) { obtention in
                    PuceCritere(libelle: LibellesFiltres.nom(obtention), etat: brouillon.locaux.obtention == obtention ? .retenu : .neutre) {
                        brouillon.locaux.obtention = obtention
                    }
                }
            }
            Flux {
                PuceCritere(libelle: "Télé : peu importe", etat: brouillon.locaux.tele == .indifferent ? .retenu : .neutre) { brouillon.locaux.tele = .indifferent }
                PuceCritere(libelle: "Ce soir", etat: brouillon.locaux.tele == .ceSoir ? .retenu : .neutre) { brouillon.locaux.tele = .ceSoir }
                PuceCritere(libelle: "Cette semaine", etat: brouillon.locaux.tele == .cetteSemaine ? .retenu : .neutre) { brouillon.locaux.tele = .cetteSemaine }
            }
            Flux {
                PuceCritere(libelle: "Vus et pas vus", etat: brouillon.locaux.dejaVu == .tous ? .retenu : .neutre) { brouillon.locaux.dejaVu = .tous }
                PuceCritere(libelle: "Pas vus", etat: brouillon.locaux.dejaVu == .pasVus ? .retenu : .neutre) { brouillon.locaux.dejaVu = .pasVus }
                PuceCritere(libelle: "Déjà vus", etat: brouillon.locaux.dejaVu == .vus ? .retenu : .neutre) { brouillon.locaux.dejaVu = .vus }
            }
        }
    }

    private var tri: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tri").font(.headline)
                Spacer()
                Button {
                    brouillon.decroissant.toggle()
                } label: {
                    Label(brouillon.decroissant ? "Décroissant" : "Croissant",
                          systemImage: brouillon.decroissant ? "arrow.down" : "arrow.up")
                        .font(.footnote)
                }
                .tint(.secondary)
            }
            Flux {
                ForEach(CriteresDecouverte.Tri.allCases, id: \.self) { tri in
                    PuceCritere(libelle: LibellesFiltres.nom(tri).capitalized, etat: brouillon.tri == tri ? .retenu : .neutre) {
                        brouillon.tri = tri
                    }
                }
            }
        }
    }

    private var boutonVoir: some View {
        Button {
            appliquer(brouillon)
            dismiss()
        } label: {
            HStack {
                Spacer()
                if comptageEnCours && nombre == nil {
                    ProgressView().tint(.black)
                } else {
                    Text(libelleVoir).font(.headline)
                }
                Spacer()
            }
            .frame(height: 56)
            .foregroundStyle(.black)
            .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("voirResultats")
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            // Le contenu défile sous le bouton : un fondu puis le fond de l'écran le gardent lisible.
            VStack(spacing: 0) {
                LinearGradient(colors: [Theme.fond.opacity(0), Theme.fond], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                Theme.fond
            }
            .padding(.top, -28)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private var libelleVoir: String {
        let mot = brouillon.type == .film ? "films" : "séries"
        guard let nombre else { return "Voir les \(mot)" }
        // TMDB plafonne le nombre annoncé à 20 001.
        if nombre >= 20_000 { return "Voir plus de 20 000 \(mot)" }
        if brouillon.filtresAppActifs, !brouillon.partDUneListeLocale, !brouillon.personnesParFilmographie {
            return "Voir les \(mot) (≤ \(nombre.formatted()))"
        }
        return nombre == 1 ? "Voir 1 \(brouillon.type == .film ? "film" : "série")" : "Voir \(nombre.formatted()) \(mot)"
    }

    // MARK: Actions

    private func compter() async {
        guard let client = etat.tmdb else { return }
        comptageEnCours = true
        defer { comptageEnCours = false }
        // Attente courte : le curseur envoie une valeur à chaque déplacement.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let resultat = await modele.compter(brouillon, client: client, contexte: contexte, abonnements: abonnements.map(\.providerID))
        guard !Task.isCancelled else { return }
        nombre = resultat
    }

    private func chercherPersonnes() async {
        guard let client = etat.tmdb, recherchePersonne.count >= 2 else {
            personnesTrouvees = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let deja = Set(brouillon.personnes.map(\.id))
        let resultats = (try? await client.rechercherTout(recherchePersonne)) ?? []
        personnesTrouvees = Array(resultats.compactMap(\.personne).filter { !deja.contains($0.id) }.prefix(5))
    }

    private func enregistrer() {
        let nom = nomEnregistrement.trimmingCharacters(in: .whitespaces)
        guard !nom.isEmpty else { return }
        contexte.insert(FiltreEnregistre(nom: nom, filtres: brouillon, abonnements: abonnements.map(\.providerID)))
        contexte.sauver()
        nomEnregistrement = ""
    }
}

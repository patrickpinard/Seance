import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Ce soir » : ce que tu as choisi de regarder ce soir, en grandes cartes, sous la rangée de tes soirées (la même que
/// celle du programme TV) : un jour marqué a quelque chose de prévu, le toucher montre sa soirée. Pour choisir, « Ajouter » réunit les rendez-vous du
/// jour, tes épisodes, ta liste regardable et des idées selon tes goûts ; la page, elle, reste ta sélection.
struct CeSoirView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]
    @Query(sort: \Echeance.date) private var echeances: [Echeance]
    @AppStorage(Prenom.cle) private var prenom = ""
    @State private var soiree = SoireeModele()
    @State private var idees = IdeesModele()
    @State private var ajout = false
    /// Le titre dont on choisit la soirée dans le calendrier.
    @State private var aDater: SelectionSoir?
    /// Le film qu'on vient de marquer regardé : c'est le bon moment pour le noter.
    @State private var filmANoter: FicheFilm?

    private var selection: [SelectionSoir] {
        let jour = ServiceSoiree.soiree()
        return selections.filter { $0.soiree == jour }
    }

    /// Le jour touché dans la rangée des soirées ; `nil` pour ce soir.
    @State private var jourChoisi: Date?

    /// Le jour de la soirée en cours, à minuit : une soirée va de 6 h à 6 h.
    private var aujourdhui: Date {
        Calendar.current.startOfDay(for: ServiceSoiree.jour(ServiceSoiree.soiree()) ?? .now)
    }

    /// Le jour affiché : jamais dans le passé, même si la page est restée ouverte jusqu'au lendemain.
    private var jour: Date {
        max(jourChoisi ?? aujourdhui, aujourdhui)
    }

    private var soireeAffichee: String {
        ServiceSoiree.soiree(jour: jour.addingTimeInterval(12 * 3600))
    }

    private var ceSoirAffiche: Bool {
        soireeAffichee == ServiceSoiree.soiree()
    }

    private var titresAffiches: [SelectionSoir] {
        let soiree = soireeAffichee
        return selections.filter { $0.soiree == soiree }
    }

    /// Les soirées passées de la semaine, pas encore tranchées : « Hier soir · Heat — regardé ? ».
    private var enAttente: [SelectionSoir] {
        let ceSoir = ServiceSoiree.soiree()
        return selections.filter { $0.soiree < ceSoir }.sorted { $0.soiree > $1.soiree }
    }

    /// Nombre de titres par soirée, pour marquer les jours du calendrier.
    private var prevus: [String: Int] {
        Dictionary(grouping: selections.filter { $0.soiree >= ServiceSoiree.soiree() }, by: \.soiree).mapValues(\.count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if etat.tmdb == nil {
                    InviteCleTMDB()
                } else {
                    contenu
                }
            }
            .background(Theme.fond)
            .navigationTitle("Ce soir")
            .boutonBarreLaterale()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ajout = true } label: {
                        Label("Ajouter", systemImage: "plus")
                    }
                    .disabled(etat.tmdb == nil)
                    .help("Ajouter un film ou une série à ta soirée")
                }
            }
            .destinationsTitres()
            .task(id: etat.tmdb != nil) { await soiree.charger(etat: etat, contexte: contexte) }
            // Un titre ajouté ailleurs (fiche, Mes listes, clic droit) : son « où regarder » est lu à son arrivée.
            .onChange(of: selection.map(\.reference)) { Task { await soiree.charger(etat: etat, contexte: contexte) } }
            // L'image de fond et la durée des titres prévus, pour les grandes cartes.
            .task(id: selections.map(\.reference)) { await etat.decors.charger(selections.map(\.reference), client: etat.tmdb) }
            .task(id: selections.count) { _ = try? ServiceSoiree(contexte: contexte).enAttente() }
            // Un rappel le jour de chaque soirée prévue, à l'heure des alertes.
            .task(id: selections.map(\.soiree)) { await etat.alertes.programmerRappelsSoirees(contexte: contexte) }
            .sheet(isPresented: $ajout) {
                AjouterASoiree(soiree: soiree, idees: idees, depart: jour.addingTimeInterval(12 * 3600))
            }
            .sheet(item: $aDater) { titre in
                ChoixSoiree(titre: titre.titre, depart: ServiceSoiree.jour(titre.soiree) ?? .now) { jour in
                    deplacer(titre, vers: jour)
                }
            }
        }
    }

    /// Grandes cartes : une colonne sur l'iPhone, deux ou trois sur le Mac.
    private static let colonnesCartes = [GridItem(.adaptive(minimum: 300, maximum: 560), spacing: 14, alignment: .top)]

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BandeSoirees(jour: Binding { jour } set: { jourChoisi = $0 == aujourdhui ? nil : $0 }, aujourdhui: aujourdhui, prevus: prevus)
                soireeDuJour
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: titresAffiches.map(\.reference))
        }
        .refreshable { await soiree.charger(etat: etat, contexte: contexte) }
    }

    /// La soirée du jour choisi : sa date, ses grandes cartes, et de quoi en ajouter.
    private var soireeDuJour: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ceSoirAffiche ? LibelleSoiree.jour(jour) : LibelleSoiree.soiree(soireeAffichee))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Theme.degradeAccent)
                Text(resume)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if ceSoirAffiche {
                ForEach(enAttente) { titre in
                    CarteSoireePassee(titre: titre, decor: etat.decors.decor(titre.reference)) {
                        Task { await marquerVu(titre) }
                    } ceSoir: {
                        deplacer(titre, vers: nil)
                    } retirer: {
                        retirer(titre)
                    }
                    .frame(maxWidth: 560)
                }
            }

            if ceSoirAffiche, let film = filmANoter {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Tu as regardé « \(film.titre) ». Ta note ?").font(.headline).lineLimit(2)
                        Spacer()
                        Button("Plus tard") { filmANoter = nil }
                            .font(.subheadline)
                            .tint(.secondary)
                    }
                    HStack(spacing: 5) {
                        ForEach(1...10, id: \.self) { valeur in
                            Button { noter(film, valeur) } label: {
                                Text("\(valeur)")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Note \(valeur) sur 10")
                        }
                    }
                    Text("Ta note affine tes goûts et les idées du soir.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 720)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
                .transition(.opacity)
            }

            if titresAffiches.isEmpty {
                if !ceSoirAffiche || filmANoter == nil { vide }
            } else {
                LazyVGrid(columns: Self.colonnesCartes, spacing: 14) {
                    ForEach(titresAffiches) { titre in
                        CarteSoiree(titre: titre, decor: etat.decors.decor(titre.reference),
                                    rendezVous: ceSoirAffiche ? rendezVous(titre.reference) : nil,
                                    ou: ceSoirAffiche ? soiree.ou[titre.reference] : nil,
                                    episode: episode(titre.reference)?.numero,
                                    minutesEpisode: episode(titre.reference)?.minutes,
                                    peutMarquerVu: titre.reference.type == .film || episode(titre.reference) != nil,
                                    note: titre.reference.type != .serie ? nil
                                        : soiree.enCours ? "Recherche du prochain épisode…" : "Tous les épisodes diffusés sont vus",
                                    ramener: ceSoirAffiche ? nil : { deplacer(titre, vers: nil) }) {
                            Task { await marquerVu(titre) }
                        } dater: {
                            aDater = titre
                        } retirer: {
                            retirer(titre)
                        }
                    }
                }
                Flux(espacement: 10) {
                    Button { ajout = true } label: {
                        Label("Ajouter un autre titre", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    boutonSurprise
                }
                .foregroundStyle(Theme.accentClair)
            }
        }
    }

    /// « 2 titres pour ce soir · 2 h 02 de film », « Dans 7 jours · 1 titre », « Rien de prévu pour l'instant ».
    private var resume: String {
        let titres = titresAffiches
        let jours = Calendar.current.dateComponents([.day], from: aujourdhui, to: jour).day ?? 0
        let quand = ceSoirAffiche ? nil : jours > 1 ? "Dans \(jours) jours" : nil
        guard !titres.isEmpty else { return [quand, "Rien de prévu pour l'instant"].compactMap { $0 }.joined(separator: " · ") }
        var morceaux = [quand, ceSoirAffiche ? "\(Format.pluriel(titres.count, "titre")) pour ce soir" : Format.pluriel(titres.count, "titre")].compactMap { $0 }
        // Le film en entier, et un seul épisode par série : c'est ce que la soirée dure vraiment.
        let minutes = titres.compactMap { $0.reference.type == .film ? etat.decors.decor($0.reference)?.minutes : episode($0.reference)?.minutes }.reduce(0, +)
        if minutes > 0 { morceaux.append("\(HeuresTele.duree(minutes)) au programme") }
        return morceaux.joined(separator: " · ")
    }

    private var vide: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.degradeAccent)
            Text(Prenom.interpeller(ceSoirAffiche ? "Rien de prévu ce soir" : "Rien de prévu ce soir-là", Prenom.lire(prenom)))
                .font(.title3.weight(.bold))
            Text(ceSoirAffiche ? "Choisis ce que tu regardes ce soir, ou touche un autre jour pour préparer sa soirée."
                 : "Choisis ce que tu regarderas ce soir-là : Séance te le rappellera le jour venu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            boutonSurprise
                .foregroundStyle(Theme.accentClair)
            Button { ajout = true } label: {
                Label("Choisir quoi regarder", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(Theme.degradeAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: 720)
    }

    /// « Surprends-moi » : un titre tiré au sort parmi ceux de ta liste qui sont regardables ce soir-là.
    private var boutonSurprise: some View {
        Button { surprendre() } label: {
            Label("Surprends-moi", systemImage: "dice")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Tire au sort un titre de ta liste, regardable ce soir")
        .accessibilityHint("Tire au sort un titre de ta liste, regardable ce soir")
    }

    private func surprendre() {
        let dejaLa = Set(titresAffiches.map(\.reference))
        guard let tire = soiree.disponibles.filter({ !dejaLa.contains($0.id) }).randomElement() else {
            etat.confirmer(soiree.enCours ? "Un instant : Séance regarde ce qui est disponible…"
                                          : "Rien d'autre de regardable dans ta liste : ouvre « Ajouter » pour des idées",
                           symbole: "dice")
            return
        }
        let jourVise = soireeAffichee
        try? ServiceSoiree(contexte: contexte).retenir(tire.id, titre: tire.titre, cheminAffiche: tire.cheminAffiche, soiree: jourVise)
        soiree.noterOu(tire.id, tire.ou)
        etat.confirmer("Le sort a choisi « \(tire.titre) »", symbole: "dice.fill") { [contexte] in
            try? ServiceSoiree(contexte: contexte).retirer(tire.id, soiree: jourVise)
        }
    }

    // MARK: Données

    private func episode(_ reference: ReferenceTitre) -> SoireeModele.Episode? {
        soiree.episodes.first { $0.id == reference }
    }

    /// Ce qui se passe ce soir pour ce titre : passage TV ou sortie du jour, sinon l'épisode à regarder.
    private func rendezVous(_ reference: ReferenceTitre) -> String? {
        let calendrier = Calendar.current
        if let echeance = echeances.first(where: { $0.reference == reference && calendrier.isDateInToday($0.date) }) { return echeance.libelle }
        if let episode = episode(reference) { return episode.libelle }
        return nil
    }

    /// Regardé : le film est marqué vu, ou le prochain épisode coché ; le titre quitte la soirée.
    private func marquerVu(_ titre: SelectionSoir) async {
        let reference = titre.reference
        if let episode = episode(reference) {
            await soiree.marquerVu(episode, etat: etat, contexte: contexte)
            // Un épisode, pas la série : elle quitte la soirée, et un toucher suffit pour enchaîner sur le suivant.
            let nom = titre.titre
            let affiche = titre.cheminAffiche
            let jour = titre.soiree
            etat.confirmer("Épisode \(episode.numero) vu · encore un ?", symbole: "checkmark", libelleAction: "Encore un") { [contexte] in
                try? ServiceSoiree(contexte: contexte).retenir(reference, titre: nom, cheminAffiche: affiche, soiree: jour)
            }
        } else if reference.type == .film, let tmdb = etat.tmdb {
            guard let film = try? await tmdb.film(reference.tmdbID, complements: [.casting]) else {
                etat.confirmer("TMDB ne répond pas : réessaie dans un instant", symbole: "exclamationmark.triangle")
                return
            }
            // Une soirée passée : le film a été vu ce soir-là, à l'heure du film.
            let quand = titre.soiree < ServiceSoiree.soiree() ? ServiceSoiree.jour(titre.soiree)?.addingTimeInterval(9 * 3600) : nil
            try? ServiceSuivi(contexte: contexte).marquerVu(film: film, le: quand ?? .now)
            etat.confirmer("« \(titre.titre) » marqué vu", symbole: "eye.fill")
            // Vu : il ne doit plus revenir dans les idées de la soirée.
            idees.retirer(reference)
            withAnimation(.snappy) { filmANoter = film }
        } else if titre.soiree >= ServiceSoiree.soiree() {
            return
        }
        try? ServiceSoiree(contexte: contexte).retirer(reference, soiree: titre.soiree)
    }

    private func noter(_ film: FicheFilm, _ valeur: Int) {
        try? ServiceSuivi(contexte: contexte).noter(film: film, note: valeur)
        etat.confirmer("« \(film.titre) » noté \(valeur)/10", symbole: "star.fill")
        withAnimation(.snappy) { filmANoter = nil }
    }

    private func retirer(_ titre: SelectionSoir) {
        let reference = titre.reference
        let nom = titre.titre
        let affiche = titre.cheminAffiche
        let jour = titre.soiree
        try? ServiceSoiree(contexte: contexte).retirer(reference, soiree: jour)
        etat.confirmer("« \(nom) » retiré de ta soirée", symbole: "moon") { [contexte] in
            try? ServiceSoiree(contexte: contexte).retenir(reference, titre: nom, cheminAffiche: affiche, soiree: jour)
        }
    }

    /// Prévoit le titre pour un autre jour ; `nil` le ramène à ce soir.
    private func deplacer(_ titre: SelectionSoir, vers jour: Date?) {
        let reference = titre.reference
        let nom = titre.titre
        let affiche = titre.cheminAffiche
        let avant = titre.soiree
        let apres = jour.map { ServiceSoiree.soiree(jour: $0) } ?? ServiceSoiree.soiree()
        guard apres != avant else { return }
        try? ServiceSoiree(contexte: contexte).retenir(reference, titre: nom, cheminAffiche: affiche, soiree: apres)
        etat.confirmer(apres == ServiceSoiree.soiree() ? "« \(nom) » passe à ce soir" : "« \(nom) » prévu \(libelle(apres).lowercased())",
                       symbole: "calendar") { [contexte] in
            try? ServiceSoiree(contexte: contexte).retenir(reference, titre: nom, cheminAffiche: affiche, soiree: avant)
        }
    }

    private func libelle(_ soiree: String) -> String {
        LibelleSoiree.soiree(soiree)
    }
}

/// « Ajouter » : tout ce qui peut rejoindre la soirée, hors de la page. Rendez-vous du jour, épisodes, ta liste
/// regardable ce soir, des idées selon tes goûts, et Explorer pour chercher autre chose.
private struct AjouterASoiree: View {
    let soiree: SoireeModele
    let idees: IdeesModele

    @Environment(EtatApp.self) private var etat
    @Environment(\.dismiss) private var fermer
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]
    /// Le jour de la soirée à remplir : celui que montre la page.
    @State private var jour: Date
    @State private var recherche = RechercheSoireeModele()
    @Environment(\.modelContext) private var contexte

    init(soiree: SoireeModele, idees: IdeesModele, depart: Date) {
        self.soiree = soiree
        self.idees = idees
        _jour = State(initialValue: max(depart, Calendar.current.startOfDay(for: .now)))
    }

    /// `nil` pour ce soir : les rendez-vous du jour et « regardable ce soir » s'appliquent.
    private var soireeChoisie: String? {
        let choisie = ServiceSoiree.soiree(jour: jour)
        return choisie <= ServiceSoiree.soiree() ? nil : choisie
    }

    /// Déjà dans la soirée ou proposés plus haut : les idées ne les répètent pas.
    private var dejaMontres: Set<ReferenceTitre> {
        let jour = soireeChoisie ?? ServiceSoiree.soiree()
        return Set(selections.filter { $0.soiree == jour }.map(\.reference))
            .union(soiree.disponibles.map(\.id))
            .union(soiree.episodes.map(\.id))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DatePicker(selection: $jour, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date) {
                        Label(soireeChoisie == nil ? "Pour ce soir" : "Pour la soirée du", systemImage: "calendar")
                            .font(.headline)
                    }
                    .tint(Theme.accent)
                    .environment(\.locale, Locale(identifier: "fr_CH"))
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    ChampRechercheSoiree(modele: recherche)

                    if recherche.texteNettoye.count >= 2 {
                        ResultatsRechercheSoiree(modele: recherche, soiree: soireeChoisie)
                    } else {
                        PropositionsSoiree(modele: soiree, soiree: soireeChoisie)
                        SectionIdees(modele: idees, dejaMontres: dejaMontres, soiree: soireeChoisie) { reference, ou in soiree.noterOu(reference, ou) }
                    }
                    Button {
                        fermer()
                        etat.rechercheDemandee = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.headline)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 34, height: 34)
                                .background(Theme.accent.opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chercher dans Explorer").font(.headline)
                                Text("Par genre, acteur, plateforme ou chaîne de TV.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.fond)
            .titreDeFeuille("Ajouter à ma soirée")
            // Sans cela, la place d'un grand titre restait vide au-dessus de la date : un tiers d'écran perdu.
            .navigationBarTitleDisplayMode(.inline)
            .task(id: recherche.texte) {
                let exclus = (try? ServiceGouts(contexte: contexte).contexteCandidats().exclus) ?? []
                await recherche.chercher(client: etat.tmdb, ecartes: exclus)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { fermer() }
                }
            }
            .destinationsTitres()
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.fond)
    }
}

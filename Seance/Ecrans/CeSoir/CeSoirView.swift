import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Regarder › Tout (8.0, l'ancienne page « Ce soir ») : ta soirée du jour choisi dans la rangée de Regarder, en grandes
/// cartes. « Suggestions pour ce soir » réunit les rendez-vous du jour, tes épisodes, ta liste regardable et des
/// suggestions selon tes goûts ; la page, elle, reste ta sélection, suivie de ce qui sort ou passe ce jour-là.
struct SoireeView: View {
    /// Le jour choisi dans la rangée de Regarder, à minuit.
    let jour: Date

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
    /// Vus, écartés ou reportés depuis le calcul des suggestions.
    @State private var suggestionsEcartees: Set<ReferenceTitre> = []

    private var selection: [SelectionSoir] {
        let jour = ServiceSoiree.soiree()
        return selections.filter { $0.soiree == jour }
    }

    /// Le jour de la soirée en cours, à minuit : une soirée va de 6 h à 6 h.
    private var aujourdhui: Date {
        Calendar.current.startOfDay(for: ServiceSoiree.jour(ServiceSoiree.soiree()) ?? .now)
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
        let reportees = Self.reportees(reporteesBrut)
        // « Pas maintenant » (8.2.11) : reportée à demain, la question ne revient pas avant.
        return selections.filter { $0.soiree < ceSoir && reportees[Self.cle($0)] != ceSoir }.sorted { $0.soiree > $1.soiree }
    }

    /// Les questions reportées : par titre et soirée, le jour où l'on a dit « Pas maintenant ».
    @AppStorage("soiree.reportees") private var reporteesBrut = Data()

    private static func reportees(_ donnees: Data) -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: donnees)) ?? [:]
    }

    private static func cle(_ titre: SelectionSoir) -> String { "\(titre.reference)|\(titre.soiree)" }

    private func reporter(_ titre: SelectionSoir) {
        let aujourdhui = ServiceSoiree.soiree()
        // Seules les questions d'aujourd'hui comptent : les anciens reports s'effacent.
        var reportees = Self.reportees(reporteesBrut).filter { $0.value == aujourdhui }
        reportees[Self.cle(titre)] = aujourdhui
        withAnimation { reporteesBrut = (try? JSONEncoder().encode(reportees)) ?? Data() }
    }

    var body: some View {
        Group {
            if etat.tmdb == nil {
                InviteCleTMDB()
            } else {
                contenu
            }
        }
        .background(Theme.fond)
        .task(id: etat.tmdb != nil) { await soiree.charger(etat: etat, contexte: contexte) }
        // Les suggestions de la page : calculées une fois par session, comme celles de la feuille.
        .task(id: etat.tmdb != nil) {
            lireSuggestionsEcartees()
            if !idees.charge { await idees.chercher(etat: etat, contexte: contexte) }
        }
        .onChange(of: selections.count) { lireSuggestionsEcartees() }
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

    /// Grandes cartes : une colonne sur l'iPhone, deux ou trois sur le Mac.
    private static let colonnesCartes = CarteLargeTitre.colonnes
    /// Des rangées de 340 points au moins : une colonne sur l'iPhone, deux à quatre sur l'iPad et le Mac.
    private static let colonnesListe = [GridItem(.adaptive(minimum: 340, maximum: 560), spacing: 12, alignment: .top)]

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                soireeDuJour
                    .padding(.horizontal, 20)
                aussiCeJourLa
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 14)
            // Toute la largeur de la fenêtre, comme les autres pages : la grille s'étale d'elle-même.
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(Theme.texte)
                Text(resume)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Les soirs passés à confirmer : en grille, pour occuper la largeur de l'iPad et du Mac (une colonne sur
            // l'iPhone).
            if ceSoirAffiche, !enAttente.isEmpty {
                EnTeteSection("Tu les as regardés ?")
                LazyVGrid(columns: Self.colonnesListe, alignment: .leading, spacing: 12) {
                    ForEach(enAttente) { titre in
                        CarteSoireePassee(titre: titre, decor: etat.decors.decor(titre.reference)) {
                            Task { await marquerVu(titre) }
                        } ceSoir: {
                            deplacer(titre, vers: nil)
                        } retirer: {
                            retirer(titre)
                        } plusTard: {
                            reporter(titre)
                        }
                    }
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
                    Text("Ta note affine tes goûts et les suggestions du soir.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 720)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
                .transition(.opacity)
            }

            if titresAffiches.isEmpty {
                if !ceSoirAffiche || filmANoter == nil { vide }
                suggestions
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
                suggestions
                Flux(espacement: 10) {
                    Button { ajout = true } label: {
                        Label(ceSoirAffiche ? "Suggestions pour ce soir" : "Suggestions pour ce soir-là", systemImage: "sparkles")
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

    // MARK: Aussi ce jour-là

    /// Ce qui sort, reprend ou passe à la TV ce jour-là pour tes titres : de quoi planifier la soirée.
    private var echeancesDuJour: [Echeance] {
        let calendrier = Calendar.current
        let dejaLa = Set(titresAffiches.map(\.reference))
        return echeances.filter { calendrier.isDate($0.date, inSameDayAs: jour) && !dejaLa.contains($0.reference) }
    }

    @ViewBuilder
    private var aussiCeJourLa: some View {
        let liste = echeancesDuJour
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                EnTeteSection(ceSoirAffiche ? "Aussi ce soir" : "Ce jour-là")
                LazyVGrid(columns: Self.colonnesListe, alignment: .leading, spacing: 10) {
                ForEach(liste) { echeance in
                    NavigationLink(value: echeance.reference) {
                        HStack(spacing: 12) {
                            ImageDistante(url: ImageTMDB.url(echeance.cheminAffiche, .affiche), coins: 8)
                                .frame(width: 44, height: 66)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(echeance.titre).font(.headline).foregroundStyle(Theme.texte).lineLimit(1)
                                Text(echeance.libelle).font(.subheadline).foregroundStyle(Theme.texte2).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.texte3)
                        }
                        .padding(10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                }
            }
        }
    }

    // MARK: Suggestions pour toi

    /// Les titres suggérés, sans ceux de la soirée affichée ni ceux déjà vus ou écartés depuis le calcul.
    private var suggestionsAffichees: [SuggestionClassee] {
        let dejaLa = Set(titresAffiches.map(\.reference))
        return Array((idees.resultat?.suggestions ?? [])
            .filter { !idees.retirees.contains($0.reference) && !dejaLa.contains($0.reference) && !suggestionsEcartees.contains($0.reference) }
            .prefix(10))
    }

    /// Sur la page même, à côté de « Surprends-moi » : ce que Séance te conseille d'après les acteurs que tu suis d'abord,
    /// puis tes pouces levés et tes notes — parmi ce qui est regardable sur tes plateformes. « + » l'ajoute à la soirée.
    @ViewBuilder
    private var suggestions: some View {
        let liste = suggestionsAffichees
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                EnTeteSection("Suggestions pour toi")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(liste) { suggestion in carteSuggestion(suggestion) }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            }
            .padding(.top, 6)
        } else if idees.enCours {
            Label("Séance prépare des suggestions…", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func carteSuggestion(_ suggestion: SuggestionClassee) -> some View {
        let titre = suggestion.candidat.titre
        return VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: suggestion.reference) {
                ImageDistante(url: ImageTMDB.url(titre.cheminAffiche, .affiche), coins: 12)
                    .frame(width: 120, height: 180)
                    .overlay(alignment: .topLeading) { BadgeOu(reference: suggestion.reference).padding(6) }
            }
            .buttonStyle(.plain)
            .actionsRapides(titre)
            .accessibilityLabel("\(titre.titre), \(suggestion.reference.type == .film ? "film" : "série"). \(suggestion.phrase)")
            Text(titre.titre).font(.caption.weight(.semibold)).lineLimit(2, reservesSpace: true).frame(width: 120, alignment: .leading)
            Button {
                try? ServiceSoiree(contexte: contexte).retenir(suggestion.reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, soiree: soireeAffichee)
                soiree.noterOu(suggestion.reference, idees.libelleOu(suggestion.reference))
                etat.confirmer(ceSoirAffiche ? "Ajouté à ta soirée" : "Prévu pour cette soirée", symbole: "moon.stars.fill")
            } label: {
                // Un bouton secondaire : sur une page, un seul bouton principal (charte 8.0).
                Label(ceSoirAffiche ? "Ce soir" : "Ce soir-là", systemImage: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.texte)
                    .frame(width: 120, height: 44)
                    .background(Theme.eleve, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter \(titre.titre) à la soirée")
        }
        .task { etat.ou.demander(suggestion.reference, client: etat.tmdb) }
    }

    private func lireSuggestionsEcartees() {
        guard let exclusions = try? ServiceGouts(contexte: contexte).contexteCandidats() else { return }
        suggestionsEcartees = exclusions.dejaVus.union(exclusions.exclus).union(exclusions.reportes)
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
                .font(.largeTitle).imageScale(.large)
                .foregroundStyle(Theme.texte2)
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
                Label(ceSoirAffiche ? "Suggestions pour ce soir" : "Planifier ce soir-là", systemImage: ceSoirAffiche ? "sparkles" : "plus")
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
                                          : "Rien d'autre de regardable dans ta liste : ouvre les suggestions",
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
            let coche = await soiree.marquerVu(episode, etat: etat, contexte: contexte)
            if let coche {
                let serie = episode.serie
                VuEnsemble.demander(etat, reference: reference, titre: titre.titre) { try $0.cocher([coche], serie: serie) }
            }
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
            let avant = try? ServiceSuivi(contexte: contexte).suivi(reference)
            let statutAvant = avant?.statut
            let nom = titre.titre
            let affiche = titre.cheminAffiche
            let jour = titre.soiree
            try? ServiceSuivi(contexte: contexte).marquerVu(film: film, le: quand ?? .now)
            VuEnsemble.demander(etat, reference: reference, titre: titre.titre) { try $0.marquerVu(film: film, le: quand ?? .now) }
            etat.confirmer("« \(titre.titre) » terminé", symbole: "checkmark") { [contexte] in
                try? ServiceSuivi(contexte: contexte).marquerNonVu(film: reference)
                AnnulationTitre.restaurer(reference, existait: avant != nil, statut: statutAvant, contexte: contexte)
                try? ServiceSoiree(contexte: contexte).retenir(reference, titre: nom, cheminAffiche: affiche, soiree: jour)
            }
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

/// « Suggestions pour ce soir » : tout ce qui peut rejoindre la soirée, hors de la page. Rendez-vous du jour, épisodes,
/// ta liste regardable ce soir, des suggestions selon tes goûts, et la recherche pour autre chose.
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
        _jour = State(initialValue: max(depart, Self.premierJour))
    }

    /// Le premier jour qu'on peut choisir : celui de la soirée **en cours**, pas le jour du calendrier. Entre minuit
    /// et six heures, la soirée en cours est celle de la veille (ServiceSoiree.soiree) : sans cela, « Ajouter »
    /// rangeait les titres dans la soirée du lendemain, invisible depuis « Ce soir ».
    private static var premierJour: Date {
        ServiceSoiree.jour(ServiceSoiree.soiree()) ?? Calendar.current.startOfDay(for: .now)
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
                    DatePicker(selection: $jour, in: Self.premierJour..., displayedComponents: .date) {
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
                                Text("Chercher autre chose").font(.headline)
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
            .titreDeFeuille(soireeChoisie == nil ? "Suggestions pour ce soir" : "Suggestions pour ce soir-là")
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

import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Idées pour ce soir » (EF-22 à EF-27) : des titres regardables sur tes plateformes, classés selon tes goûts, tes
/// notes et ce que tu as écarté. Sans clé Claude, tout se fait sur l'appareil ; avec, Claude lit l'envie précisée.
@MainActor
@Observable
final class IdeesModele {
    var demande = DemandeCeSoir()
    private(set) var resultat: ResultatSuggestions?
    /// Idées traitées (« je regarde », « pas ce soir », « jamais ») : la liste affiche les suivantes à leur place.
    private(set) var retirees: [ReferenceTitre] = []
    /// Où regarder chaque idée, lu sur TMDB après le classement.
    private(set) var ou: [ReferenceTitre: EtatDisponibilite] = [:]
    private(set) var enCours = false
    private(set) var erreur: String?
    private(set) var nombreCandidats = 0
    private(set) var profil = ProfilGouts()
    /// Déjà chargé une fois : revenir sur l'onglet ne relance pas la recherche.
    private(set) var charge = false

    /// Les dernières idées, gardées sur disque d'un lancement à l'autre : l'écran les montre tout de suite
    /// plutôt qu'une roue, tant qu'elles ont moins de six heures, datent du même jour et que rien n'a bougé
    /// dans les goûts, les listes ou les plateformes. Sinon, elles sont recalculées comme avant.
    private struct IdeesGardees: Codable {
        let calculeLe: Date
        let empreinte: String
        let resultat: ResultatSuggestions
        let ou: [ReferenceTitre: EtatDisponibilite]
    }

    private static let fichierIdees = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "idees-du-soir.json")
    private static let validiteIdees: TimeInterval = 6 * 3600

    /// Ce qui rend des idées périmées : les plateformes cochées, le nombre de titres suivis et de « J'aime ».
    private static func empreinte(_ contexte: ModelContext) -> String {
        let plateformes = ((try? contexte.fetch(FetchDescriptor<Abonnement>(predicate: #Predicate { $0.actif }))) ?? [])
            .map(\.providerID).sorted().map(String.init).joined(separator: ",")
        let suivis = (try? contexte.fetchCount(FetchDescriptor<Suivi>())) ?? 0
        let aimes = (try? contexte.fetchCount(FetchDescriptor<TitreAime>())) ?? 0
        return "\(plateformes)|\(suivis)|\(aimes)"
    }

    /// Reprend les idées du dernier lancement. Faux si elles manquent, ont vieilli ou ne valent plus.
    func reprendre(contexte: ModelContext) -> Bool {
        #if DEBUG
        // En démonstration (captures, tests d'interface), les idées se recalculent toujours : celles d'un
        // lancement précédent ne correspondent plus au magasin, qui vient d'être refait.
        if Demonstration.active { return false }
        #endif
        guard demande.envieNettoyee.isEmpty,
              let donnees = try? Data(contentsOf: Self.fichierIdees),
              let gardees = try? JSONDecoder().decode(IdeesGardees.self, from: donnees),
              gardees.calculeLe > Date.now.addingTimeInterval(-Self.validiteIdees),
              Calendar.current.isDateInToday(gardees.calculeLe),
              gardees.empreinte == Self.empreinte(contexte)
        else { return false }
        resultat = gardees.resultat
        ou = gardees.ou
        retirees = []
        charge = true
        return true
    }

    private func garder(contexte: ModelContext) {
        #if DEBUG
        if Demonstration.active { return }
        #endif
        guard demande.envieNettoyee.isEmpty, let resultat else { return }
        let gardees = IdeesGardees(calculeLe: .now, empreinte: Self.empreinte(contexte), resultat: resultat, ou: ou)
        guard let donnees = try? JSONEncoder().encode(gardees) else { return }
        try? donnees.write(to: Self.fichierIdees, options: .atomic)
    }

    /// Sans envie précisée, le classement reste local : pas d'appel payant à Claude à chaque ouverture.
    func chercher(etat: EtatApp, contexte: ModelContext, precise: Bool = false) async {
        guard let tmdb = etat.tmdb, !enCours else { return }
        enCours = true
        erreur = nil
        defer {
            enCours = false
            charge = true
        }
        let gouts = ServiceGouts(contexte: contexte)
        do {
            profil = try gouts.profil()
            let exclusions = try gouts.contexteCandidats()
            let candidats = try await CollecteurCandidats(client: tmdb).candidats(pour: demande, profil: profil, contexte: exclusions)
            nombreCandidats = candidats.count
            let claude = precise && !demande.envieNettoyee.isEmpty ? etat.claude : nil
            // Douze idées classées, cinq affichées : chaque idée traitée laisse sa place à la suivante.
            let nouveau = await ServiceRecommandation(claude: claude, nombre: NombreIdees.aClasser)
                .suggerer(demande, candidats: candidats, profil: profil, nomsGenres: etat.nomsGenres)
            resultat = nouveau
            retirees = []
            ou = await Self.disponibilites(nouveau.suggestions.map(\.reference), tmdb: tmdb, contexte: contexte)
            garder(contexte: contexte)
            if let resultat, claude != nil, resultat.origine == .local, let avertissement = resultat.avertissement {
                etat.journal.noter(.claude, avertissement, conseil: "Les idées viennent du classement local. Vérifie la clé Claude dans Réglages › Claude si cela se répète.")
            }
        } catch is CancellationError {
            return
        } catch {
            resultat = nil
            erreur = Journal.conseil(error) ?? "Impossible de réunir des idées pour l'instant : réessaie dans un moment."
            etat.journal.noter(.tmdb, "« Idées pour ce soir » n'a pas pu réunir de suggestions.", erreur: error)
        }
    }

    /// Une idée traitée quitte la liste ; les autres restent (EF-25).
    func retirer(_ reference: ReferenceTitre) {
        if !retirees.contains(reference) { retirees.append(reference) }
    }

    /// « Annuler » : l'idée reprend sa place.
    func restaurer(_ reference: ReferenceTitre) {
        retirees.removeAll { $0 == reference }
    }

    /// « Sur Netflix », « Sur ton NAS · 4K », « Ce soir sur M6 » : le libellé d'une idée, ou `nil` si rien n'est su.
    func libelleOu(_ reference: ReferenceTitre) -> String? {
        guard let etat = ou[reference], let libelle = RegardableCeSoir.libelle(etat) else { return nil }
        switch etat {
        case .dansAbonnements: return "Sur \(libelle)"
        case .aLaTeleBientot: return "Ce soir sur \(libelle)"
        default: return libelle
        }
    }

    /// Les plateformes de chaque idée, six appels à la fois ; une idée sans réponse reste sans libellé.
    private static func disponibilites(_ references: [ReferenceTitre], tmdb: TMDBClient, contexte: ModelContext) async -> [ReferenceTitre: EtatDisponibilite] {
        let offres = await withTaskGroup(of: (ReferenceTitre, OffresRegion?).self) { groupe in
            var reste = references[...]
            func lancer(_ reference: ReferenceTitre) {
                groupe.addTask { (reference, try? await tmdb.fournisseurs(reference.type, id: reference.tmdbID).offres()) }
            }
            for _ in 0..<6 {
                guard let reference = reste.popFirst() else { break }
                lancer(reference)
            }
            var resultat: [ReferenceTitre: OffresRegion] = [:]
            while let (reference, offre) = await groupe.next() {
                if let offre { resultat[reference] = offre }
                if let suivante = reste.popFirst() { lancer(suivante) }
            }
            return resultat
        }
        let disponibilite = ServiceDisponibilite(contexte: contexte)
        var etats: [ReferenceTitre: EtatDisponibilite] = [:]
        for reference in references {
            if let etat = try? disponibilite.etat(reference, offres: offres[reference]) { etats[reference] = etat }
        }
        return etats
    }
}

struct SectionIdees: View {
    let modele: IdeesModele
    /// Titres déjà montrés plus haut dans « Ce soir » : une idée ne les répète pas.
    let dejaMontres: Set<ReferenceTitre>
    /// La soirée à laquelle « Je regarde » ajoute le titre ; `nil` pour ce soir.
    var soiree: String?
    /// « Je regarde » : la soirée apprend où regarder le titre, pour l'afficher sous son nom.
    let jeRegarde: (ReferenceTitre, String?) -> Void

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var precisionOuverte = false
    @AppStorage(NombreIdees.cle) private var nombreIdees = NombreIdees.parDefaut
    @AppStorage(Prenom.cle) private var prenom = ""
    /// Vus, écartés ou reportés depuis le calcul des idées : la liste est gardée pour la session, pas ce qu'elle exclut.
    /// Sans cela, le film marqué « Regardé » à l'instant revenait en tête des idées.
    @State private var ecartes: Set<ReferenceTitre> = []
    /// 👍 Tes « J'aime » : le pouce d'une idée déjà aimée reste levé.
    @Query private var aimes: [TitreAime]

    /// Trois, cinq ou dix idées à la fois (Réglages › Toi), parmi celles ni traitées ni déjà montrées plus haut.
    private var idees: [SuggestionClassee] {
        Array((modele.resultat?.suggestions ?? [])
            .filter { !modele.retirees.contains($0.reference) && !dejaMontres.contains($0.reference) && !ecartes.contains($0.reference) }
            .prefix(NombreIdees.lire(nombreIdees)))
    }

    var body: some View {
        @Bindable var modele = modele
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Prenom.lire(prenom).map { "Des idées pour toi, \($0)" } ?? "Idées pour ce soir", systemImage: "sparkles")
                    .font(.title3.weight(.bold))
                    .labelStyle(EtiquetteSection())
                Spacer()
                Button {
                    Task { await modele.chercher(etat: etat, contexte: contexte, precise: !modele.demande.envieNettoyee.isEmpty) }
                } label: {
                    Label("Autres idées", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .disabled(modele.enCours)
                .help("Chercher d'autres idées")
            }

            // Film, série ou les deux : le choix relance la recherche.
            SelecteurCases(selection: Binding { modele.demande.type } set: { type in
                guard type != modele.demande.type else { return }
                modele.demande.type = type
                Task { await modele.chercher(etat: etat, contexte: contexte, precise: !modele.demande.envieNettoyee.isEmpty) }
            }, cases: [.init(valeur: nil, nom: "Films et séries"), .init(valeur: TypeTitre.film, nom: "Films"), .init(valeur: TypeTitre.serie, nom: "Séries")])

            if modele.profil.estVide, modele.charge {
                MessageEtat(texte: "Choisis tes goûts dans Préférences › Mes goûts, et note ce que tu regardes : les idées seront sur mesure.",
                            symbole: "heart")
                    .padding(.horizontal, -20)
            }

            if let erreur = modele.erreur {
                MessageEtat(texte: erreur, ton: .probleme)
                    .padding(.horizontal, -20)
            } else if modele.enCours, idees.isEmpty {
                MessageEtat(texte: "Séance cherche sur tes plateformes ce qui te ressemble…", ton: .attente)
                    .padding(.horizontal, -20)
            } else if modele.charge, idees.isEmpty {
                MessageEtat(texte: modele.resultat?.avertissement ?? "Rien de nouveau ne correspond pour l'instant. Précise ton envie ou coche d'autres plateformes.",
                            symbole: "sparkles")
                    .padding(.horizontal, -20)
            }

            ForEach(idees) { suggestion in
                CarteIdee(suggestion: suggestion, ou: modele.libelleOu(suggestion.reference).flatMap { CarteSoiree.secours($0) },
                          aime: aimes.contains { $0.reference == suggestion.reference }) { action in traiter(action, suggestion) }
            }

            DisclosureGroup(isExpanded: $precisionOuverte) {
                PrecisionEnvie(demande: $modele.demande, enCours: modele.enCours, avecClaude: etat.claude != nil) {
                    Task { await modele.chercher(etat: etat, contexte: contexte, precise: true) }
                }
                .padding(.top, 10)
            } label: {
                Label("Préciser ton envie", systemImage: "text.bubble")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(Theme.accentClair)

            if let resultat = modele.resultat, !idees.isEmpty {
                Text(resultat.origine == .claude
                     ? "Choisies par Claude parmi \(modele.nombreCandidats) \(modele.nombreCandidats > 1 ? "titres disponibles" : "titre disponible") sur tes plateformes."
                     : "Classées sur cet appareil selon tes goûts, parmi \(modele.nombreCandidats) \(modele.nombreCandidats > 1 ? "titres disponibles" : "titre disponible") sur tes plateformes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: etat.tmdb != nil) {
            if !modele.charge, !modele.reprendre(contexte: contexte) { await modele.chercher(etat: etat, contexte: contexte) }
        }
        .onAppear(perform: lireEcartes)
        .animation(.easeOut(duration: 0.25), value: idees.map(\.id))
    }

    private func lireEcartes() {
        guard let exclusions = try? ServiceGouts(contexte: contexte).contexteCandidats() else { return }
        ecartes = exclusions.dejaVus.union(exclusions.exclus).union(exclusions.reportes)
    }

    /// Les trois actions du cahier (EF-26), avec annulation.
    private func traiter(_ action: CarteIdee.Action, _ suggestion: SuggestionClassee) {
        let gouts = ServiceGouts(contexte: contexte)
        let reference = suggestion.reference
        let titre = suggestion.candidat.titre
        let avant = try? ServiceSuivi(contexte: contexte).suivi(reference)
        let statutAvant = avant?.statut
        switch action {
        case .jAime:
            // 👍 L'idée reste dans la liste : aimer n'est pas choisir pour ce soir.
            if (try? gouts.estAime(reference)) == true {
                try? gouts.nePlusAimer(reference)
            } else {
                let candidat = suggestion.candidat
                try? gouts.aimer(reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, genres: titre.genres,
                                 acteursIDs: candidat.acteurs, acteurs: candidat.acteurs.compactMap { candidat.nomsActeurs[$0] })
                etat.confirmer("Noté : tes idées en tiendront compte", symbole: "hand.thumbsup.fill")
            }
            return
        case .jeRegarde:
            _ = try? gouts.jeRegarde(suggestion.candidat)
            try? ServiceSoiree(contexte: contexte).retenir(reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, soiree: soiree)
            jeRegarde(reference, modele.libelleOu(reference))
            etat.confirmer(soiree == nil ? "Ajouté à ma soirée" : "Prévu pour cette soirée", symbole: "moon.stars.fill")
        case .pasCeSoir:
            try? gouts.reporter(reference)
            etat.confirmer("Écarté pour ce soir", symbole: "clock.arrow.circlepath") { [modele, contexte] in
                try? ServiceGouts(contexte: contexte).annulerReport(reference)
                modele.restaurer(reference)
            }
        case .dejaVu:
            // Déjà vu avant : le titre quitte les idées, nourrit les goûts, et reste hors des statistiques.
            let actions = ActionsRapides(etat: etat, contexte: contexte)
            Task { [modele] in
                await actions.executer(.dejaVuAvant, sur: titre, annulationEnPlus: { modele.restaurer(reference) })
            }
        case .jamais:
            try? gouts.jamais(reference, titre: titre.titre, genres: titre.genres, cheminAffiche: titre.cheminAffiche)
            etat.confirmer("Ne te sera plus proposé", symbole: "hand.thumbsdown.fill") { [modele, contexte] in
                AnnulationTitre.restaurer(reference, existait: avant != nil, statut: statutAvant, contexte: contexte)
                modele.restaurer(reference)
            }
        }
        modele.retirer(reference)
    }
}

/// Une idée : affiche, titre, où la regarder, raison en une phrase, et les trois gestes du soir.
private struct CarteIdee: View {
    enum Action { case jeRegarde, pasCeSoir, jamais, jAime, dejaVu }

    let suggestion: SuggestionClassee
    let ou: String?
    var aime = false
    let action: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // La grande carte 16/9, comme partout ailleurs, puis la raison de la proposition en dessous.
            NavigationLink(value: suggestion.reference) {
                CarteLargeTitre(suggestion.candidat.titre)
            }
            .buttonStyle(.plain)
            .actionsRapides(suggestion.candidat.titre)

            Text(suggestion.phrase)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            // Où la regarder, tout de suite : lire sur le NAS, ouvrir la plateforme, ou la chaîne et l'heure.
            ActionsOuRegarder(reference: suggestion.reference, titre: suggestion.candidat.titre.titre, secours: ou)

            // Compact sur l'iPhone : deux icônes rondes (nom à l'appui long) et un seul bouton écrit, sur une ligne.
            HStack(spacing: 10) {
                Spacer()
                BoutonIcone(symbole: aime ? "hand.thumbsup.fill" : "hand.thumbsup", libelle: aime ? "J'aime, noté" : "J'aime", actif: aime, taille: 36,
                            explication: "Ce titre te plaît, même sans l'avoir vu : Séance te proposera davantage de titres de ce genre.") { action(.jAime) }
                BoutonIcone(symbole: "hand.thumbsdown", libelle: "Je n'aime pas", taille: 36,
                            explication: "Ne plus jamais proposer ce titre. Séance en tient compte pour tes goûts ; Réglages › Toi permet de tout reproposer.") { action(.jamais) }
                BoutonIcone(symbole: "eye", libelle: "Déjà vu", taille: 36,
                            explication: "Tu l'as déjà vu : il sort des idées et compte dans tes goûts, sans entrer dans tes statistiques.") { action(.dejaVu) }
                BoutonIcone(symbole: "clock.arrow.circlepath", libelle: "Pas ce soir", taille: 36,
                            explication: "L'écarter pour ce soir : il pourra revenir dès demain.") { action(.pasCeSoir) }
                Button { action(.jeRegarde) } label: {
                    Label("Je regarde", systemImage: "moon.stars.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Theme.degradeAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Ajouter à ma soirée et à Mes listes")
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// L'envie en quelques mots, film ou série, durée maximale.
private struct PrecisionEnvie: View {
    @Binding var demande: DemandeCeSoir
    let enCours: Bool
    let avecClaude: Bool
    let chercher: () -> Void
    @FocusState private var saisieActive: Bool

    private static let durees: [(String, Int?)] = [("Peu importe", nil), ("Moins de 1 h 30", 90), ("Moins de 2 h", 120)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Un truc nerveux, pas trop long…", text: $demande.envie)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Theme.fond.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($saisieActive)
                .submitLabel(.search)
                .onSubmit(lancer)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PuceFiltre(libelle: "Film ou série", active: demande.type == nil) { demande.type = nil }
                    PuceFiltre(libelle: "Film", active: demande.type == .film) { demande.type = .film }
                    PuceFiltre(libelle: "Série", active: demande.type == .serie) { demande.type = .serie }
                    ForEach(Self.durees, id: \.0) { libelle, minutes in
                        PuceFiltre(libelle: libelle, active: demande.dureeMaxMinutes == minutes) { demande.dureeMaxMinutes = minutes }
                    }
                }
            }
            Button(action: lancer) {
                HStack {
                    Spacer()
                    if enCours {
                        ProgressView().tint(.black)
                    } else {
                        Label("Trouve-moi ça", systemImage: "sparkles").font(.headline)
                    }
                    Spacer()
                }
                .frame(height: 44)
                .foregroundStyle(.black)
                .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(enCours)
            Text(avecClaude
                 ? "Claude lit ton envie et choisit parmi les titres disponibles (environ 0,07 $ la demande)."
                 : "Classement sur l'appareil. Ajoute une clé Claude dans Réglages pour qu'il lise ton envie.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func lancer() {
        saisieActive = false
        guard !enCours else { return }
        chercher()
    }
}

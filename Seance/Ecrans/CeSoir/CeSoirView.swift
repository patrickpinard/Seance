import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Ce soir » : seulement ce que tu as choisi de regarder ce soir, puis tes prochaines soirées, prévues à la date
/// de ton choix. Pour choisir, « Ajouter » réunit les rendez-vous du jour, tes épisodes, ta liste regardable et
/// des idées selon tes goûts ; la page, elle, reste ta sélection.
struct CeSoirView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]
    @Query(sort: \Echeance.date) private var echeances: [Echeance]
    @State private var soiree = SoireeModele()
    @State private var idees = IdeesModele()
    @State private var ajout = false
    /// Le titre dont on choisit la soirée dans le calendrier.
    @State private var aDater: SelectionSoir?

    private var selection: [SelectionSoir] {
        let jour = ServiceSoiree.soiree()
        return selections.filter { $0.soiree == jour }
    }

    /// Les soirées à venir, la plus proche d'abord, chacune avec ses titres.
    private var prochaines: [(soiree: String, titres: [SelectionSoir])] {
        let jour = ServiceSoiree.soiree()
        let groupes = Dictionary(grouping: selections.filter { $0.soiree > jour }, by: \.soiree)
        return groupes.keys.sorted().map { ($0, groupes[$0] ?? []) }
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
            // Un rappel le jour de chaque soirée prévue, à l'heure des alertes.
            .task(id: selections.map(\.soiree)) { await etat.alertes.programmerRappelsSoirees(contexte: contexte) }
            .sheet(isPresented: $ajout) {
                AjouterASoiree(soiree: soiree, idees: idees)
            }
            .sheet(item: $aDater) { titre in
                ChoixSoiree(titre: titre.titre, depart: ServiceSoiree.jour(titre.soiree) ?? .now) { jour in
                    deplacer(titre, vers: jour)
                }
            }
        }
    }

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(Self.jourEnToutesLettres(.now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if selection.isEmpty {
                    vide
                } else {
                    ForEach(selection) { titre in
                        CarteSoiree(titre: titre, rendezVous: rendezVous(titre.reference), ou: soiree.ou[titre.reference],
                                    peutMarquerVu: titre.reference.type == .film || episode(titre.reference) != nil) {
                            Task { await marquerVu(titre) }
                        } dater: {
                            aDater = titre
                        } retirer: {
                            retirer(titre)
                        }
                    }
                    Button { ajout = true } label: {
                        Label("Ajouter un autre titre", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accentClair)
                    .padding(.top, 4)
                }

                if !prochaines.isEmpty {
                    Label("Prochaines soirées", systemImage: "calendar")
                        .font(.title3.weight(.bold))
                        .labelStyle(EtiquetteSection())
                        .padding(.top, 18)
                    ForEach(prochaines, id: \.soiree) { groupe in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(libelle(groupe.soiree))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentClair)
                            ForEach(groupe.titres) { titre in
                                LigneSoireePrevue(titre: titre) {
                                    deplacer(titre, vers: nil)
                                } dater: {
                                    aDater = titre
                                } retirer: {
                                    retirer(titre)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            // Sur le Mac, une colonne lisible plutôt que des cartes étirées sur toute la fenêtre.
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: selection.map(\.reference))
        }
        .refreshable { await soiree.charger(etat: etat, contexte: contexte) }
    }

    private var vide: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.degradeAccent)
            Text("Rien de prévu ce soir").font(.title3.weight(.bold))
            Text("Choisis ce que tu regardes ce soir : la page ne montre que ta sélection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
    }

    // MARK: Données

    private func episode(_ reference: ReferenceTitre) -> SoireeModele.Episode? {
        soiree.episodes.first { $0.id == reference }
    }

    /// Ce qui se passe ce soir pour ce titre : passage télé ou sortie du jour, sinon l'épisode à regarder.
    private func rendezVous(_ reference: ReferenceTitre) -> String? {
        let calendrier = Calendar.current
        if let echeance = echeances.first(where: { $0.reference == reference && calendrier.isDateInToday($0.date) }) { return echeance.libelle }
        if let episode = episode(reference) { return "Épisode \(episode.numero) à regarder" }
        return nil
    }

    /// Regardé : le film est marqué vu, ou le prochain épisode coché ; le titre quitte la soirée.
    private func marquerVu(_ titre: SelectionSoir) async {
        let reference = titre.reference
        if let episode = episode(reference) {
            await soiree.marquerVu(episode, etat: etat, contexte: contexte)
            etat.confirmer("Épisode \(episode.numero) marqué vu", symbole: "checkmark")
        } else if reference.type == .film, let tmdb = etat.tmdb {
            guard let film = try? await tmdb.film(reference.tmdbID, complements: [.casting]) else {
                etat.confirmer("TMDB ne répond pas : réessaie dans un instant", symbole: "exclamationmark.triangle")
                return
            }
            try? ServiceSuivi(contexte: contexte).marquerVu(film: film)
            etat.confirmer("« \(titre.titre) » marqué vu", symbole: "eye.fill")
        } else {
            return
        }
        try? ServiceSoiree(contexte: contexte).retirer(reference)
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

    /// « Demain », « Samedi 20 septembre ».
    private func libelle(_ soiree: String) -> String {
        guard let jour = ServiceSoiree.jour(soiree) else { return soiree }
        if ServiceSoiree.soiree(jour: Date.now.addingTimeInterval(86_400)) == soiree, ServiceSoiree.soiree() != soiree { return "Demain" }
        return Self.jourEnToutesLettres(jour)
    }

    /// « Vendredi 18 septembre » : majuscule au jour seulement, comme on l'écrit en français.
    private static func jourEnToutesLettres(_ date: Date) -> String {
        let texte = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH")))
        return texte.prefix(1).uppercased() + texte.dropFirst()
    }
}

/// Un titre de la soirée : affiche, ce qui se passe ce soir, où le regarder ; « vu » et « retirer ».
private struct CarteSoiree: View {
    let titre: SelectionSoir
    let rendezVous: String?
    let ou: String?
    let peutMarquerVu: Bool
    let vu: () -> Void
    let dater: () -> Void
    let retirer: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            NavigationLink(value: titre.reference) {
                HStack(spacing: 14) {
                    ImageDistante(url: ImageTMDB.url(titre.cheminAffiche, .affiche), coins: 10)
                        .frame(width: 70, height: 105)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(titre.titre).font(.headline).lineLimit(2)
                        Text(titre.reference.type == .film ? "Film" : "Série")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let rendezVous {
                            Text(rendezVous)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentClair)
                                .lineLimit(1)
                        }
                        // Le passage télé dit déjà où regarder : pas de doublon.
                        if let ou, ou != rendezVous, !(rendezVous?.hasPrefix("Sur ") == true && ou.hasPrefix("Ce soir sur")) {
                            Label(ou, systemImage: ou.hasPrefix("Ce soir") ? "tv" : ou.hasPrefix("Sur le NAS") ? "externaldrive.fill" : "play.tv")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 10) {
                if peutMarquerVu {
                    BoutonIcone(symbole: "checkmark", libelle: "Regardé", principal: true, taille: 36,
                                explication: "Marquer comme regardé : le film est vu, ou l'épisode coché, et le titre quitte ta soirée.", action: vu)
                }
                BoutonIcone(symbole: "calendar", libelle: "Prévoir pour une autre soirée", taille: 36,
                            explication: "Choisir la date à laquelle tu veux le regarder.", action: dater)
                BoutonIcone(symbole: "xmark", libelle: "Retirer de ma soirée", taille: 36,
                            explication: "Retirer ce titre de ta soirée. Il reste dans Mes listes.", action: retirer)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Un titre prévu pour une soirée à venir : le ramener à ce soir, changer sa date, ou le retirer.
private struct LigneSoireePrevue: View {
    let titre: SelectionSoir
    let ceSoir: () -> Void
    let dater: () -> Void
    let retirer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: titre.reference) {
                HStack(spacing: 12) {
                    ImageDistante(url: ImageTMDB.url(titre.cheminAffiche, .affiche), coins: 8)
                        .frame(width: 44, height: 66)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(titre.titre).font(.headline).lineLimit(2)
                        Text(titre.reference.type == .film ? "Film" : "Série").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            BoutonIcone(symbole: "moon.stars.fill", libelle: "Regarder ce soir", taille: 34,
                        explication: "Ramener ce titre à la soirée de ce soir.", action: ceSoir)
            BoutonIcone(symbole: "calendar", libelle: "Changer la date", taille: 34,
                        explication: "Choisir une autre soirée.", action: dater)
            BoutonIcone(symbole: "xmark", libelle: "Retirer", taille: 34,
                        explication: "Retirer ce titre de cette soirée. Il reste dans Mes listes.", action: retirer)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Le calendrier d'une soirée : à partir d'aujourd'hui.
private struct ChoixSoiree: View {
    let titre: String
    let choisir: (Date) -> Void

    @Environment(\.dismiss) private var fermer
    @State private var jour: Date

    init(titre: String, depart: Date, choisir: @escaping (Date) -> Void) {
        self.titre = titre
        self.choisir = choisir
        _jour = State(initialValue: max(depart, Calendar.current.startOfDay(for: .now)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Quel soir veux-tu regarder « \(titre) » ?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                DatePicker("Soirée", selection: $jour, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
                    .environment(\.locale, Locale(identifier: "fr_CH"))
                Button {
                    choisir(jour)
                    fermer()
                } label: {
                    Text("Prévoir pour \(jour.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))))")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Theme.fond)
            .titreDeFeuille("Choisir la soirée")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { fermer() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.fond)
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
    /// Le jour de la soirée à remplir : ce soir par défaut.
    @State private var jour = Date.now

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

                    PropositionsSoiree(modele: soiree, soiree: soireeChoisie)
                    SectionIdees(modele: idees, dejaMontres: dejaMontres, soiree: soireeChoisie) { reference, ou in soiree.noterOu(reference, ou) }
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
                                Text("Chercher un titre").font(.headline)
                                Text("Dans Explorer ; clic droit ou 🌙 sur sa fiche pour l'ajouter à ta soirée.")
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

import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Ce soir » sur la TV : la soirée en grandes affiches, puis les soirées à venir.
struct CeSoirTV: View {
    @Query(sort: \SelectionSoir.ajouteLe) private var soirees: [SelectionSoir]
    @Query private var fichiers: [FichierNAS]
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte

    @State private var jourChoisi: String?
    /// « Idées pour ce soir » (EF-22 à EF-27), comme sur l'iPhone : classées sur l'appareil selon tes goûts.
    @State private var idees: [SuggestionClassee] = []
    @State private var ideesEnCours = false

    var body: some View {
        let groupes = parSoiree
        let choisi = jourChoisi.flatMap { j in groupes.contains { $0.soiree == j } ? j : nil } ?? groupes.first?.soiree
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 44) {
                if groupes.isEmpty {
                    VideTV(symbole: "moon.stars.fill", titre: "Rien de prévu",
                           message: "Choisis une idée ci-dessous, ou ajoute un titre à ta soirée depuis sa fiche, ici ou sur ton iPhone.")
                } else {
                    // La même rangée de jours que sur l'iPhone : ce soir et les soirées déjà prévues.
                    ScrollView(.horizontal) {
                        HStack(spacing: 24) {
                            ForEach(groupes, id: \.soiree) { groupe in
                                Button { jourChoisi = groupe.soiree } label: {
                                    TuileJourTV(nom: Self.nomCourt(groupe.soiree), numero: Self.quantieme(groupe.soiree),
                                                detail: groupe.titres.count > 1 ? "\(groupe.titres.count) titres" : "1 titre")
                                }
                                .buttonStyle(BoutonTV(principal: groupe.soiree == choisi, hauteur: nil))
                            }
                        }
                        .padding(.horizontal, MargesTV.bord)
                        .padding(.vertical, 20)
                    }
                    .scrollClipDisabled()
                    .focusSection()

                    if let choisi, let groupe = groupes.first(where: { $0.soiree == choisi }) {
                        EtagereTV(titre: libelle(choisi), sousTitre: groupe.titres.count > 1 ? "\(groupe.titres.count) titres pour cette soirée" : "1 titre") {
                            ForEach(groupe.titres, id: \.reference) { selection in
                                NavigationLink(value: selection.reference) {
                                    CarteLargeTV(surtitre: surLeNAS(selection.reference) ? "Sur ton NAS" : nil, titre: selection.titre,
                                                 detail: nil, cheminImage: selection.cheminAffiche,
                                                 marque: surLeNAS(selection.reference) ? "externaldrive.fill" : nil,
                                                 largeur: CarteLargeTV.largeurGrille)
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                }
                etagereIdees(dejaPrevus: Set(soirees.map(\.reference)))
            }
            .padding(.vertical, 40)
        }
        .task(id: etat.tmdb != nil) { await chercherIdees() }
    }

    /// Des titres regardables sur tes plateformes, selon tes notes et tes pouces. L'affiche ouvre la fiche : « Ce soir »,
    /// 👍 et 👎 s'y trouvent.
    @ViewBuilder
    private func etagereIdees(dejaPrevus: Set<ReferenceTitre>) -> some View {
        let proposees = idees.filter { !dejaPrevus.contains($0.reference) }
        if !proposees.isEmpty {
            EtagereTV(titre: "Idées pour ce soir", sousTitre: "Sur tes plateformes, selon tes goûts — ouvre une fiche pour l'ajouter à ta soirée") {
                ForEach(proposees) { idee in
                    NavigationLink(value: idee.reference) {
                        CarteLargeTV(surtitre: nil, titre: idee.candidat.titre.titre,
                                     detail: idee.reference.type == .film ? "Film" : "Série",
                                     cheminImage: idee.candidat.titre.cheminFond ?? idee.candidat.titre.cheminAffiche,
                                     marque: surLeNAS(idee.reference) ? "externaldrive.fill" : nil,
                                     largeur: CarteLargeTV.largeurGrille)
                    }
                    .buttonStyle(.card)
                }
                Button { Task { await chercherIdees(force: true) } } label: {
                    VStack(spacing: 14) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 54, weight: .semibold))
                        Text("Autres idées").font(.system(size: 26, weight: .semibold))
                    }
                    .frame(width: AfficheTV.largeur, height: AfficheTV.largeur * 1.5)
                }
                .buttonStyle(.card)
            }
        } else if ideesEnCours {
            Text("Séance cherche des idées sur tes plateformes…").font(.system(size: 26)).foregroundStyle(.secondary)
                .padding(.horizontal, MargesTV.bord)
        }
    }

    private func chercherIdees(force: Bool = false) async {
        guard let tmdb = etat.tmdb, !ideesEnCours, force || idees.isEmpty else { return }
        ideesEnCours = true
        defer { ideesEnCours = false }
        let gouts = ServiceGouts(contexte: contexte)
        guard let profil = try? gouts.profil(), let exclusions = try? gouts.contexteCandidats(),
              let candidats = try? await CollecteurCandidats(client: tmdb).candidats(pour: DemandeCeSoir(), profil: profil, contexte: exclusions)
        else { return }
        let resultat = await ServiceRecommandation(claude: nil, nombre: 12)
            .suggerer(DemandeCeSoir(), candidats: force ? candidats.shuffled() : candidats, profil: profil, nomsGenres: GenresParDefaut.noms)
        idees = resultat.suggestions
    }

    private static func quantieme(_ soiree: String) -> Int {
        Calendar.current.component(.day, from: ServiceSoiree.jour(soiree) ?? .now)
    }

    private static func nomCourt(_ soiree: String) -> String {
        if soiree == ServiceSoiree.soiree() { return "Ce soir" }
        if soiree == ServiceSoiree.soiree(.now.addingTimeInterval(86_400)) { return "Demain" }
        guard let jour = ServiceSoiree.jour(soiree) else { return "" }
        return jour.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_CH"))).capitalized
    }

    private var parSoiree: [(soiree: String, titres: [SelectionSoir])] {
        let ceSoir = ServiceSoiree.soiree()
        return Dictionary(grouping: soirees.filter { $0.soiree >= ceSoir }, by: \.soiree)
            .map { (soiree: $0.key, titres: $0.value) }
            .sorted { $0.soiree < $1.soiree }
    }

    private func libelle(_ soiree: String) -> String {
        if soiree == ServiceSoiree.soiree() { return "Ce soir" }
        guard let jour = ServiceSoiree.jour(soiree) else { return soiree }
        if soiree == ServiceSoiree.soiree(.now.addingTimeInterval(86_400)) { return "Demain" }
        return jour.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))).capitalized(with: Locale(identifier: "fr_CH"))
    }

    private func surLeNAS(_ reference: ReferenceTitre) -> Bool {
        fichiers.contains { $0.reference == reference }
    }
}

/// « Un autre soir… » depuis une fiche : les sept prochains soirs en tuiles, comme la rangée de jours de l'iPhone.
struct ChoixSoireeTV: View {
    let titre: String
    let choisir: (Date) -> Void

    @Environment(\.dismiss) private var fermer

    private var jours: [Date] {
        let depart = Calendar.current.startOfDay(for: ServiceSoiree.jour(ServiceSoiree.soiree()) ?? .now).addingTimeInterval(12 * 3600)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: depart) }
    }

    var body: some View {
        VStack(spacing: 50) {
            VStack(spacing: 10) {
                Text("Quel soir ?").font(.system(size: 58, weight: .heavy))
                Text("« \(titre) » t'attendra dans Ce soir, ce jour-là.").font(.system(size: 28)).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                ForEach(Array(jours.enumerated()), id: \.offset) { rang, jour in
                    Button {
                        choisir(jour)
                        fermer()
                    } label: {
                        TuileJourTV(nom: rang == 0 ? "Ce soir" : rang == 1 ? "Demain"
                                        : jour.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_CH"))).capitalized,
                                    numero: Calendar.current.component(.day, from: jour),
                                    detail: jour.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "fr_CH"))))
                    }
                    .buttonStyle(BoutonTV(principal: rang == 0, hauteur: nil))
                }
            }
            Button("Annuler") { fermer() }.buttonStyle(BoutonTV())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.fond.ignoresSafeArea())
        .onExitCommand { fermer() }
    }
}

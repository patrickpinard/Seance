import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Regarder › Tout sur la TV (8.0, l'ancienne page « Ce soir ») : la soirée du jour choisi dans la rangée de Regarder,
/// en grandes cartes, puis des suggestions. Des sections sans défilement propre : Regarder les empile dans sa page.
struct SectionsSoireeTV: View {
    /// La soirée choisie, sous la clé de `ServiceSoiree.soiree(jour:)`.
    let soiree: String

    @Query(sort: \SelectionSoir.ajouteLe) private var soirees: [SelectionSoir]
    @Query private var fichiers: [FichierNAS]
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte

    /// « Suggestions pour ce soir » (maquette 8.0, n° 5) : un panneau par-dessus Regarder.
    @State private var suggestions = false

    private var ceSoir: Bool { soiree == ServiceSoiree.soiree() }

    var body: some View {
        let titres = soirees.filter { $0.soiree == soiree }
        Group {
            if titres.isEmpty {
                // Maquette 8.0, n° 4 : un encadré, et « Planifier » comme action principale.
                VStack(alignment: .leading, spacing: 18) {
                    Text(ceSoir ? "Ta soirée" : "\(libelle(soiree)) · ta soirée").font(.system(size: 38, weight: .bold))
                    VStack(spacing: 14) {
                        Text("Rien de prévu").font(.system(size: 32, weight: .bold))
                        Text("Un film, une série, un documentaire ?").font(.system(size: 24)).foregroundStyle(Theme.texte2)
                        Button { suggestions = true } label: {
                            Label(ceSoir ? "Suggestions pour ce soir" : "Planifier ce soir-là", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BoutonTV(principal: true))
                    }
                    .padding(30)
                    .frame(width: 720)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.trait, lineWidth: 1))
                }
                .padding(.horizontal, MargesTV.bord)
                .focusSection()
            } else {
                EtagereTV(titre: (ceSoir ? "Ta soirée" : "\(libelle(soiree)) · ta soirée") + " · " + (titres.count > 1 ? "\(titres.count) titres" : "1 titre")) {
                    ForEach(titres, id: \.reference) { selection in
                        NavigationLink(value: selection.reference) {
                            CarteLargeTV(surtitre: nil, titre: selection.titre, detail: selection.reference.type == .film ? "Film" : "Série",
                                         cheminImage: selection.cheminAffiche, largeur: CarteLargeTV.largeurGrille, reference: selection.reference)
                        }
                        .buttonStyle(.card)
                        .menuCarteTV(selection.reference, titre: selection.titre, cheminAffiche: selection.cheminAffiche, soiree: soiree)
                    }
                    // En bout de rangée, un bouton gris : les suggestions pour ce soir.
                    Button { suggestions = true } label: {
                        Label(ceSoir ? "Suggestions pour ce soir" : "Suggestions pour ce soir-là", systemImage: "sparkles")
                    }
                    .buttonStyle(BoutonTV())
                    .frame(height: CarteLargeTV.largeurGrille * 9 / 16)
                }
            }
        }
        .fullScreenCover(isPresented: $suggestions) { PanneauSuggestionsTV(soiree: soiree) }
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

/// « Suggestions pour ce soir » (maquette 8.0, n° 5) : un panneau par-dessus Regarder, Tout · Films · Séries ·
/// Documentaires en haut, l'envie à dicter à Siri, les cartes dessous. Un clic ajoute à la soirée, l'appui long ouvre
/// la fiche (dans le panneau, qui a sa pile).
struct PanneauSuggestionsTV: View {
    let soiree: String

    enum Categorie: String, CaseIterable { case tout = "Tout", films = "Films", series = "Séries", documentaires = "Documentaires" }

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var fermer
    @Query(sort: \SelectionSoir.ajouteLe) private var soirees: [SelectionSoir]
    @State private var categorie = Categorie.tout
    @State private var envie = ""
    @State private var idees: [SuggestionClassee] = []
    @State private var enCours = false
    @State private var chemin = NavigationPath()

    private var ceSoir: Bool { soiree == ServiceSoiree.soiree() }

    var body: some View {
        NavigationStack(path: $chemin) {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Text(ceSoir ? "Suggestions pour ce soir" : "Suggestions pour ce soir-là").font(.system(size: 44, weight: .heavy))
                        Spacer()
                        HStack(spacing: 12) {
                            ForEach(Categorie.allCases, id: \.self) { choix in
                                Button(choix.rawValue) { categorie = choix }
                                    .buttonStyle(BoutonTV(principal: categorie == choix, hauteur: 56))
                            }
                        }
                        .focusSection()
                    }
                    TextField("Une envie ? Dis-la à Siri : « un thriller pas trop long »", text: $envie)
                    let prevus = Set(soirees.filter { $0.soiree == soiree }.map(\.reference))
                    let liste = idees.filter { !prevus.contains($0.reference) }
                    if liste.isEmpty {
                        Text(enCours ? "Séance cherche des suggestions sur tes plateformes…" : "Aucune suggestion pour l'instant.")
                            .font(.system(size: 26)).foregroundStyle(Theme.texte2)
                    }
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 34) {
                            ForEach(liste) { idee in
                                Button {
                                    try? ServiceSoiree(contexte: contexte).retenir(idee.reference, titre: idee.candidat.titre.titre,
                                                                                    cheminAffiche: idee.candidat.titre.cheminAffiche, soiree: soiree)
                                    etat.dire("« \(idee.candidat.titre.titre) » ajouté à ta soirée")
                                } label: {
                                    CarteLargeTV(surtitre: nil, titre: idee.candidat.titre.titre,
                                                 detail: idee.reference.type == .film ? "Film" : "Série",
                                                 cheminImage: idee.candidat.titre.cheminFond ?? idee.candidat.titre.cheminAffiche,
                                                 largeur: 420, reference: idee.reference)
                                }
                                .buttonStyle(.card)
                                .contextMenu {
                                    Button { chemin.append(idee.reference) } label: { Label("Voir la fiche", systemImage: "info.circle") }
                                }
                            }
                        }
                        .padding(.vertical, 30)
                    }
                    .scrollClipDisabled()
                    .focusSection()
                    Text("Clic : l'ajouter à ta soirée · appui long : voir la fiche").font(.system(size: 22)).foregroundStyle(Theme.texte2)
                    Spacer(minLength: 0)
                }
                .padding(50)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Theme.trait, lineWidth: 1))
                .padding(.horizontal, 90)
                .padding(.vertical, 70)
            }
            .navigationDestination(for: ReferenceTitre.self) { FicheTV(reference: $0).pageOuverte() }
            .navigationDestination(for: PersonneTVRef.self) { PersonneTV(personne: $0).pageOuverte() }
        }
        .onExitCommand { if chemin.isEmpty { fermer() } }
        .task(id: Cle(categorie: categorie, envie: envie)) {
            if !envie.isEmpty { try? await Task.sleep(for: .milliseconds(600)) }
            guard !Task.isCancelled else { return }
            await chercher()
        }
    }

    private struct Cle: Hashable { let categorie: Categorie; let envie: String }

    private func chercher() async {
        guard let tmdb = etat.tmdb else { return }
        enCours = true
        defer { enCours = false }
        let type: TypeTitre? = switch categorie {
        case .films: .film
        case .series: .serie
        case .tout, .documentaires: nil
        }
        let demande = DemandeCeSoir(envie: envie, type: type)
        let gouts = ServiceGouts(contexte: contexte)
        guard let profil = try? gouts.profil(), let exclusions = try? gouts.contexteCandidats(),
              let candidats = try? await CollecteurCandidats(client: tmdb).candidats(pour: demande, profil: profil, contexte: exclusions)
        else { return }
        let resultat = await ServiceRecommandation(claude: nil, nombre: 16)
            .suggerer(demande, candidats: candidats, profil: profil, nomsGenres: GenresParDefaut.noms)
        idees = resultat.suggestions.filter { idee in
            let documentaire = idee.candidat.titre.genres.contains(99)
            return categorie == .documentaires ? documentaire : true
        }
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
                Text("« \(titre) » t'attendra dans Regarder, ce jour-là.").font(.system(size: 28)).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                ForEach(Array(jours.enumerated()), id: \.offset) { rang, jour in
                    Button {
                        choisir(jour)
                        fermer()
                    } label: {
                        TuileJourTV(nom: rang == 0 ? "Auj." : rang == 1 ? "Demain"
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

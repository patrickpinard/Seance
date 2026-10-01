import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Qui est-ce ? » (8.9) : à la pause d'un film ou d'un épisode du NAS, les visages de ce qu'on regarde, au-dessus de
/// la barre de lecture. Un visage ouvre un panneau à droite — qui c'est, et où tu l'as déjà vu —, sans quitter le
/// lecteur : la fiche complète de la personne ouvrirait d'autres titres, et une seconde lecture par-dessus la première.
enum VisagesLectureTV {
    /// Le casting du film, ou celui de la série et les invités de l'épisode. Les mêmes compléments que la fiche, pour
    /// que la réponse vienne du cache de TMDB quand on est passé par elle.
    static func charger(reference: ReferenceTitre?, saison numeroSaison: Int?, episode: Int?, tmdb: TMDBClient) async -> [PersonneCasting] {
        guard let reference else { return [] }
        switch reference.type {
        case .film:
            let fiche = try? await tmdb.film(reference.tmdbID)
            return QuiEstCe.visages(casting: fiche?.casting)
        case .serie:
            async let serie = try? tmdb.serie(reference.tmdbID, complements: [.fournisseurs, .casting, .videos])
            var invites: [PersonneCasting] = []
            if let numero = numeroSaison, let episode, let saison = try? await tmdb.saison(numero, serie: reference.tmdbID) {
                invites = saison.episodes.first { $0.numero == episode }?.invites ?? []
            }
            return QuiEstCe.visages(casting: await serie?.casting, invites: invites)
        }
    }
}

/// La rangée des visages, posée au-dessus du titre dans la barre du lecteur, le temps de la pause.
struct RangeeVisagesTV: View {
    let titre: String
    let visages: [PersonneCasting]
    let choisir: (PersonneCasting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 30) {
                    ForEach(visages) { personne in
                        Button { choisir(personne) } label: { VisageTV(personne: personne) }
                            .buttonStyle(StyleVisageTV())
                            .accessibilityLabel([personne.nom, QuiEstCe.role(personne)].compactMap { $0 }.joined(separator: ", "))
                            .accessibilityHint("Où tu l'as déjà vu")
                    }
                }
                .padding(.vertical, 24)
            }
            .frame(height: 230)
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

/// Un rond, le nom dessous et son rôle ici ; au focus, le rond se cerne de blanc et grandit (charte de la TV).
private struct VisageTV: View {
    let personne: PersonneCasting
    @Environment(\.isFocused) private var aLeFocus

    var body: some View {
        VStack(spacing: 10) {
            ImageTV(url: ImageTMDB.url(personne.cheminPortrait, .affiche), symboleVide: "person.fill")
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay { if aLeFocus { Circle().strokeBorder(.white, lineWidth: 5) } }
            VStack(spacing: 2) {
                Text(personne.nom).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                Text(QuiEstCe.role(personne) ?? " ").font(.system(size: 20)).foregroundStyle(Theme.texte2)
            }
            .lineLimit(1)
        }
        .frame(width: 170)
    }
}

private struct StyleVisageTV: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Corps(configuration: configuration) }
    private struct Corps: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var aLeFocus
        var body: some View {
            configuration.label
                .scaleEffect(aLeFocus ? 1.1 : (configuration.isPressed ? 0.95 : 1))
                .shadow(color: .black.opacity(aLeFocus ? 0.45 : 0), radius: 14, y: 8)
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}

/// Le panneau de droite : portrait, nom, rôle ici, puis « Tu l'as vu dans » — tes films et séries vus où il joue — et
/// « Connu pour » ; « Reprendre la lecture » le referme et relance l'image, comme la touche Lecture.
struct PanneauPersonneTV: View {
    let personne: PersonneCasting
    /// Le titre qu'on regarde, qui ne compte pas dans « Tu l'as vu dans ».
    let actuel: ReferenceTitre?
    let reprendre: () -> Void

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var suivis: [Suivi]
    @Query private var visionnages: [Visionnage]
    @Query private var acteursSuivis: [ActeurSuivi]
    @State private var fiche: FichePersonne?
    @State private var filmographie: Filmographie?
    @State private var erreur: String?
    @FocusState private var reprise: Bool

    /// Vu : un visionnage, une série entamée ou un titre terminé.
    private var vus: Set<ReferenceTitre> {
        Set(visionnages.map { ReferenceTitre(type: $0.type, tmdbID: $0.tmdbID) })
            .union(suivis.filter { $0.statut == .termine || $0.statut == .enCours }.map(\.reference))
    }

    private var suivi: Bool { acteursSuivis.contains { $0.personneID == personne.id } }

    private var dejaVu: [CreditPersonne] {
        filmographie.map { QuiEstCe.dejaVu(dans: $0, vus: vus, sauf: actuel) } ?? []
    }

    /// Ses titres les plus connus que tu n'as pas vus, pour situer quelqu'un qu'on ne connaît pas encore.
    private var connuPour: [CreditPersonne] {
        guard let filmographie else { return [] }
        let deja = Set(dejaVu.map(\.reference))
        return filmographie.roles
            .filter { !deja.contains($0.reference) && $0.reference != actuel && $0.cheminAffiche != nil }
            .sorted { ($0.nombreVotes ?? 0) > ($1.nombreVotes ?? 0) }
            .prefix(4).map { $0 }
    }

    /// « Acteur · 52 ans ».
    private var faits: String {
        var faits: [String] = []
        if let domaine = fiche?.domaine { faits.append(domaine == "Directing" ? "Réalisateur" : domaine == "Acting" ? "Acteur" : domaine) }
        if let age = fiche?.age(aujourdhui: DateTMDB(.now)) { faits.append(fiche?.dateDeces == nil ? "\(age) ans" : "mort à \(age) ans") }
        return faits.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 28) {
                    ImageTV(url: ImageTMDB.url(personne.cheminPortrait ?? fiche?.cheminPortrait, .afficheGrande), symboleVide: "person.fill")
                        .frame(width: 170, height: 170)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 8) {
                        Text(fiche?.nom ?? personne.nom).font(.system(size: 40, weight: .heavy)).lineLimit(2)
                        if let role = QuiEstCe.role(personne) {
                            Text("Ici : \(role)").font(.system(size: 24)).foregroundStyle(.white).lineLimit(2)
                        }
                        if !faits.isEmpty { Text(faits).font(.system(size: 22)).foregroundStyle(Theme.texte2) }
                    }
                }
                VStack(spacing: 14) {
                    Button { reprendre() } label: { Label("Reprendre la lecture", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(BoutonTV(principal: true))
                        .focused($reprise)
                    Button { basculerSuivi() } label: {
                        Label(suivi ? "Suivi" : "Suivre", systemImage: suivi ? "bell.fill" : "bell").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BoutonTV())
                }
                .focusSection()
                if let erreur {
                    Text(erreur).font(.system(size: 24)).foregroundStyle(Theme.texte2)
                } else if filmographie == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    section("Tu l'as vu dans", dejaVu.prefix(8).map { $0 },
                            vide: "Aucun de tes films ni de tes séries vus. C'est une découverte.")
                    if !connuPour.isEmpty { section("Connu pour", connuPour, vide: nil) }
                }
            }
            .padding(50)
        }
        .frame(width: 760)
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
        // Opaque : on lit le panneau, pas l'image de dessous.
        .background(Theme.surface)
        .background(Theme.fond)
        .ignoresSafeArea()
        .task(id: personne.id) { await charger() }
        .onAppear { reprise = true }
    }

    /// Des affiches en grille, à regarder seulement : le lecteur reste ouvert, on n'y lance rien.
    @ViewBuilder
    private func section(_ titre: String, _ credits: [CreditPersonne], vide: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(titre).font(.system(size: 28, weight: .bold))
            if credits.isEmpty, let vide {
                Text(vide).font(.system(size: 24)).foregroundStyle(Theme.texte2)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(150), spacing: 22, alignment: .top), count: 4), alignment: .leading, spacing: 22) {
                    ForEach(credits, id: \.reference) { credit in
                        VStack(alignment: .leading, spacing: 8) {
                            ImageTV(url: ImageTMDB.url(credit.cheminAffiche, .affiche))
                                .aspectRatio(2 / 3, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(credit.titre).font(.system(size: 20, weight: .semibold)).lineLimit(2)
                            if let annee = credit.date?.annee {
                                Text(String(annee)).font(.system(size: 18)).foregroundStyle(Theme.texte2)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func charger() async {
        guard let client = etat.tmdb else { erreur = "Il faut d'abord la clé TMDB : Réglages › TMDB."; return }
        // Le portrait et l'âge sont un plus : sans eux, le panneau garde le nom, le rôle et la filmographie.
        async let lue = try? client.personne(personne.id)
        do {
            filmographie = try await client.filmographie(personne: personne.id)
            fiche = await lue
        } catch {
            erreur = "TMDB ne répond pas. Vérifie la connexion de l'Apple TV."
        }
    }

    private func basculerSuivi() {
        let service = ServiceActeurs(contexte: contexte)
        let nom = fiche?.nom ?? personne.nom
        if suivi {
            try? service.nePlusSuivre(personne.id)
            etat.dire("Tu ne suis plus \(nom)")
        } else {
            try? service.suivre(personneID: personne.id, nom: nom, cheminPortrait: fiche?.cheminPortrait ?? personne.cheminPortrait)
            etat.dire("\(nom) : suivi. Ton iPhone te préviendra de ses prochains films.")
        }
    }
}

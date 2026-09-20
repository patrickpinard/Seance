import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// La fiche d'un titre sur la TV (EF-143) : l'image en grand, l'essentiel en quelques lignes, et les actions à portée
/// de télécommande — lire le fichier du NAS, prévoir pour ce soir, garder à voir, marquer vu.
struct FicheTV: View {
    let reference: ReferenceTitre

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.openURL) private var ouvrir
    @Query private var fichiers: [FichierNAS]
    @Query private var suivis: [Suivi]
    @Query private var soirees: [SelectionSoir]
    @Query private var abonnements: [Abonnement]

    @State private var film: FicheFilm?
    @State private var serie: SerieDetail?
    @State private var erreur: String?
    @State private var vu = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            fond
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Spacer().frame(height: 300)
                    entete
                    actions
                    if let synopsis, !synopsis.isEmpty {
                        Text(synopsis).font(.system(size: 29)).foregroundStyle(.white.opacity(0.85)).lineSpacing(6).frame(maxWidth: 1250, alignment: .leading)
                    }
                    if reference.type == .serie, !episodesNAS.isEmpty { episodes }
                    if let erreur { Text(erreur).font(.system(size: 26)).foregroundStyle(.orange) }
                }
                .padding(.horizontal, MargesTV.bord)
                .padding(.bottom, 80)
            }
        }
        .background(Theme.fond.ignoresSafeArea())
        .task(id: reference) { await charger() }
    }

    // MARK: Morceaux

    /// L'image de fond du titre ; à défaut (certains titres n'en ont pas), son affiche, cadrée large et plus assombrie.
    private var fond: some View {
        let cheminFond = film?.cheminFond ?? serie?.cheminFond ?? siens.first?.cheminFond
        let url = ImageTMDB.url(cheminFond, .fondGrand) ?? ImageTMDB.url(cheminAffiche, .afficheGrande)
        return ImageTV(url: url, symboleVide: "")
            .frame(maxWidth: .infinity)
            .frame(height: 760)
            .overlay {
                LinearGradient(stops: [.init(color: Theme.fond.opacity(cheminFond == nil ? 0.45 : 0), location: 0),
                                       .init(color: Theme.fond.opacity(cheminFond == nil ? 0.75 : 0.55), location: 0.45),
                                       .init(color: Theme.fond, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre).font(.system(size: 76, weight: .heavy)).lineLimit(2)
            Text(ligneFaits).font(.system(size: 30, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            if !plateformes.isEmpty {
                Label("Dans tes abonnements : " + plateformes.joined(separator: ", "), systemImage: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.accentClair)
            }
        }
        .foregroundStyle(.white)
    }

    private var actions: some View {
        HStack(spacing: 28) {
            // Un film du NAS : la lecture d'abord, c'est pour elle qu'on est devant la TV.
            if reference.type == .film, let fichier = siens.first {
                Button { lire(fichier) } label: { Label("Lire", systemImage: "play.fill") }
                    .buttonStyle(BoutonTV(principal: true))
            }
            Button { basculerSoiree() } label: {
                Label(prevuCeSoir ? "Retirer de ce soir" : "Ce soir", systemImage: prevuCeSoir ? "moon.stars.fill" : "moon.stars")
            }
            if suivi == nil {
                Button { garder() } label: { Label("À voir", systemImage: "bookmark") }
            }
            if reference.type == .film {
                Button { basculerVu() } label: { Label(vu ? "Vu" : "Marquer vu", systemImage: vu ? "checkmark.circle.fill" : "checkmark.circle") }
            }
        }
        .buttonStyle(BoutonTV())
        .focusSection()
    }

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sur ton NAS").font(.system(size: 38, weight: .bold))
            ForEach(episodesNAS, id: \.chemin) { fichier in
                HStack(spacing: 24) {
                    Text(numero(fichier)).font(.system(size: 28, weight: .bold)).monospacedDigit().frame(width: 150, alignment: .leading)
                    Text(fichier.qualite ?? "").font(.system(size: 24)).foregroundStyle(.secondary)
                    Spacer()
                    Button { lire(fichier) } label: { Label("Lire", systemImage: "play.fill") }
                        .buttonStyle(BoutonTV(principal: true))
                }
                .font(.system(size: 26))
            }
        }
        .frame(maxWidth: 1250, alignment: .leading)
        .focusSection()
    }

    // MARK: Données

    private var siens: [FichierNAS] { fichiers.filter { $0.reference == reference } }
    private var episodesNAS: [FichierNAS] {
        siens.filter { $0.saison != nil && $0.episode != nil }.sorted { ($0.saison ?? 0, $0.episode ?? 0) < ($1.saison ?? 0, $1.episode ?? 0) }
    }
    private var suivi: Suivi? { suivis.first { $0.reference == reference } }
    private var prevuCeSoir: Bool { soirees.contains { $0.reference == reference && $0.soiree == ServiceSoiree.soiree() } }

    private var titre: String { film?.titre ?? serie?.nom ?? siens.first?.titre ?? suivi?.titre ?? "…" }
    private var synopsis: String? { film?.synopsis ?? serie?.synopsis }
    private var cheminAffiche: String? { film?.cheminAffiche ?? serie?.cheminAffiche ?? siens.first?.cheminAffiche ?? suivi?.cheminAffiche }

    private var ligneFaits: String {
        var faits: [String] = [reference.type == .film ? "Film" : "Série"]
        if let minutes = film?.dureeMinutes, minutes > 0 { faits.append(minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min") }
        if let serie { faits.append(serie.nombreSaisons > 1 ? "\(serie.nombreSaisons) saisons" : "1 saison") }
        let genres = (film?.genres ?? serie?.genres ?? []).prefix(3).map(\.nom)
        if !genres.isEmpty { faits.append(genres.joined(separator: ", ")) }
        let note = film?.noteMoyenne ?? serie?.noteMoyenne ?? 0
        if note > 0 { faits.append("\(Int((note * 10).rounded())) % sur TMDB") }
        if !siens.isEmpty { faits.append("Sur ton NAS") }
        return faits.joined(separator: "  ·  ")
    }

    /// Les plateformes où le titre est inclus, en Suisse, parmi celles cochées sur l'iPhone (arrivées par la synchronisation).
    private var plateformes: [String] {
        guard let offres = (film?.fournisseurs ?? serie?.fournisseurs)?.offres() else { return [] }
        let cochees = Set(abonnements.filter(\.actif).map(\.providerID))
        return offres.abonnement.filter { cochees.contains($0.id) }.map(\.nom)
    }

    private func numero(_ fichier: FichierNAS) -> String {
        "S\(String(format: "%02d", fichier.saison ?? 0))E\(String(format: "%02d", fichier.episode ?? 0))"
    }

    // MARK: Actions

    private func charger() async {
        vu = (try? ServiceSuivi(contexte: contexte).estVu(reference)) ?? false
        guard let client = etat.tmdb else { return }
        do {
            switch reference.type {
            case .film: film = try await client.film(reference.tmdbID)
            case .serie: serie = try await client.serie(reference.tmdbID, complements: [.fournisseurs])
            }
        } catch {
            erreur = "La fiche n'a pas pu être lue sur TMDB. Vérifie la connexion de l'Apple TV."
        }
    }

    /// Dans l'app choisie dans Réglages › Lecture, et elle seule.
    private func lire(_ fichier: FichierNAS) {
        guard let url = etat.lien(pour: fichier) else {
            etat.dire(etat.lecteur == .infuse ? "Infuse ne s'ouvre que sur un titre reconnu. Choisis VLC dans Réglages › Lecture."
                                              : "Le mot de passe du NAS manque : vois Réglages › NAS.")
            return
        }
        etat.noterLecture(fichier)
        ouvrir(url) { accepte in
            if !accepte { etat.dire("\(etat.lecteur.nom) n'est pas installé sur cette Apple TV, ou refuse ce lien.") }
        }
    }

    private func basculerSoiree() {
        let service = ServiceSoiree(contexte: contexte)
        if prevuCeSoir {
            try? service.retirer(reference)
            etat.dire("« \(titre) » retiré de ta soirée")
        } else {
            try? service.retenir(reference, titre: titre, cheminAffiche: cheminAffiche)
            etat.dire("« \(titre) » ajouté à ta soirée")
        }
    }

    private func garder() {
        let service = ServiceSuivi(contexte: contexte)
        if let film { _ = try? service.suivre(film: film) } else if let serie { _ = try? service.suivre(serie: serie) } else { return }
        etat.dire("« \(titre) » gardé dans « À voir »")
    }

    private func basculerVu() {
        guard let film else { return }
        let service = ServiceSuivi(contexte: contexte)
        if vu { try? service.marquerNonVu(film: reference) } else { try? service.marquerVu(film: film) }
        vu.toggle()
        etat.dire(vu ? "« \(titre) » marqué vu" : "« \(titre) » de nouveau à voir")
    }
}

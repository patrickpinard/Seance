import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce que la fiche affiche, qu'il s'agisse d'un film ou d'une série.
struct FicheAffichee {
    var reference: ReferenceTitre
    var titre: String
    var accroche: String?
    var synopsis: String
    var cheminAffiche: String?
    var cheminFond: String?
    var annee: Int?
    var genres: [String]
    var duree: String?
    var pourcentage: Int
    var offres: OffresRegion?
    var casting: [PersonneCasting]
    var langueOriginale: String
    var film: FicheFilm?
    var serie: SerieDetail?

    init(film: FicheFilm) {
        reference = film.reference
        titre = film.titre
        accroche = film.accroche
        synopsis = film.synopsis
        cheminAffiche = film.cheminAffiche
        cheminFond = film.cheminFond
        annee = film.dateSortie?.annee
        genres = film.genres.map(\.nom)
        duree = film.dureeMinutes.map { "\($0 / 60) h \(String(format: "%02d", $0 % 60))" }
        pourcentage = Int((film.noteMoyenne * 10).rounded())
        offres = film.fournisseurs?.offres()
        casting = film.casting?.principaux(15) ?? []
        langueOriginale = film.langueOriginale
        self.film = film
    }

    init(serie: SerieDetail) {
        reference = serie.reference
        titre = serie.nom
        synopsis = serie.synopsis
        cheminAffiche = serie.cheminAffiche
        cheminFond = serie.cheminFond
        annee = serie.saisons.compactMap(\.dateDiffusion).min()?.annee
        genres = serie.genres.map(\.nom)
        duree = "\(serie.nombreSaisons) saison\(serie.nombreSaisons > 1 ? "s" : "")"
        pourcentage = Int((serie.noteMoyenne * 10).rounded())
        offres = serie.fournisseurs?.offres()
        casting = serie.casting?.principaux(15) ?? []
        langueOriginale = serie.langueOriginale
        self.serie = serie
    }
}

struct FicheView: View {
    let reference: ReferenceTitre
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var fiche: FicheAffichee?
    @State private var erreur: String?

    var body: some View {
        Group {
            if let fiche {
                ContenuFiche(fiche: fiche)
            } else if let erreur {
                ContentUnavailableView("Fiche indisponible", systemImage: "wifi.exclamationmark", description: Text(erreur))
            } else {
                ProgressView()
            }
        }
        .background(Theme.fond)
        .task(id: reference) { await charger() }
    }

    private func charger() async {
        guard let client = etat.tmdb else {
            erreur = "Clé TMDB manquante."
            return
        }
        do {
            switch reference.type {
            case .film:
                fiche = FicheAffichee(film: try await client.film(reference.tmdbID))
            case .serie:
                fiche = FicheAffichee(serie: try await client.serie(reference.tmdbID, complements: [.casting, .fournisseurs, .videos]))
            }
        } catch {
            erreur = error.localizedDescription
        }
    }
}

private struct ContenuFiche: View {
    let fiche: FicheAffichee
    @Environment(\.modelContext) private var contexte
    @State private var etatDisponibilite: EtatDisponibilite = .introuvable
    @State private var suivi: Suivi?
    @State private var vu = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                enTete
                actions
                BlocOuRegarder(etat: etatDisponibilite)
                if let accroche = fiche.accroche, !accroche.isEmpty {
                    Text(accroche).italic().foregroundStyle(.secondary).padding(.horizontal, 20)
                }
                if !fiche.synopsis.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Synopsis").font(.headline)
                        Text(fiche.synopsis).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                }
                if !fiche.casting.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection("Casting")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(fiche.casting) { personne in
                                    CartePersonne(personne: personne)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                Text("Disponibilités : JustWatch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .task { rafraichir() }
    }

    /// UX-06 : image de fond, affiche, titre, année, genres, durée et anneau de note.
    private var enTete: some View {
        ZStack(alignment: .bottomLeading) {
            ImageDistante(url: ImageTMDB.url(fiche.cheminFond, .fondGrand), coins: 0)
                .frame(height: 300)
                .clipped()
            LinearGradient(colors: [.clear, Theme.fond.opacity(0.7), Theme.fond], startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
            HStack(alignment: .bottom, spacing: 16) {
                ImageDistante(url: ImageTMDB.url(fiche.cheminAffiche, .affiche))
                    .frame(width: 110, height: 165)
                    .shadow(radius: 12)
                VStack(alignment: .leading, spacing: 6) {
                    Text(fiche.titre).font(.title2.weight(.heavy)).lineLimit(3)
                    Text([fiche.annee.map(String.init), fiche.duree].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(fiche.genres.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    AnneauNote(pourcentage: fiche.pourcentage, diametre: 44)
                }
            }
            .padding(.horizontal, 20)
            .offset(y: 60)
        }
        .padding(.bottom, 60)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                basculerAVoir()
            } label: {
                Label(suivi == nil ? "À voir" : "Dans mes listes", systemImage: suivi == nil ? "plus" : "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let film = fiche.film {
                Button {
                    marquerVu(film)
                } label: {
                    Label(vu ? "Vu" : "Marquer vu", systemImage: vu ? "eye.fill" : "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .sensoryFeedback(.success, trigger: vu)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
    }

    private func rafraichir() {
        let suiviService = ServiceSuivi(contexte: contexte)
        suivi = try? suiviService.suivi(fiche.reference)
        vu = (try? suiviService.estVu(fiche.reference)) ?? false
        etatDisponibilite = (try? ServiceDisponibilite(contexte: contexte).etat(fiche.reference, offres: fiche.offres)) ?? .introuvable
    }

    private func basculerAVoir() {
        let service = ServiceSuivi(contexte: contexte)
        if let suivi {
            contexte.delete(suivi)
            try? contexte.save()
        } else if let film = fiche.film {
            _ = try? service.suivre(film: film)
        } else if let serie = fiche.serie {
            _ = try? service.suivre(serie: serie)
        }
        rafraichir()
    }

    private func marquerVu(_ film: FicheFilm) {
        guard !vu else { return }
        try? ServiceSuivi(contexte: contexte).marquerVu(film: film)
        rafraichir()
    }
}

/// EF-73 : l'état de disponibilité en tête du bloc « Où regarder ».
private struct BlocOuRegarder: View {
    let etat: EtatDisponibilite

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Où regarder").font(.headline)
            HStack(spacing: 12) {
                Image(systemName: icone).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.subheadline.weight(.semibold))
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    private var icone: String {
        switch etat {
        case .surNAS: "externaldrive.fill"
        case .dansAbonnements: "play.tv.fill"
        case .aLaTeleBientot: "tv"
        case .aLouerOuAcheter: "cart"
        case .introuvable: "questionmark.circle"
        }
    }

    private var titre: String {
        switch etat {
        case .surNAS: "Sur le NAS"
        case .dansAbonnements: "Dans tes abonnements"
        case .aLaTeleBientot: "À la télé bientôt"
        case .aLouerOuAcheter: "À louer ou acheter"
        case .introuvable: "Introuvable légalement en Suisse"
        }
    }

    private var detail: String? {
        switch etat {
        case .surNAS(let qualite): qualite.map { "Qualité \($0)" }
        case .dansAbonnements(let fournisseurs): fournisseurs.map(\.nom).joined(separator: ", ")
        case .aLaTeleBientot(let diffusion):
            "\(diffusion.chaine), \(diffusion.debut.formatted(.dateTime.weekday(.wide).hour().minute()))"
        case .aLouerOuAcheter(let location, let achat):
            Array(Set((location + achat).map(\.nom))).sorted().joined(separator: ", ")
        case .introuvable: nil
        }
    }
}

private struct CartePersonne: View {
    let personne: PersonneCasting

    var body: some View {
        VStack(spacing: 6) {
            ImageDistante(url: ImageTMDB.url(personne.cheminPortrait, .portrait), coins: 40)
                .frame(width: 80, height: 80)
            Text(personne.nom).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
            if let role = personne.personnage, !role.isEmpty {
                Text(role).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 90)
    }
}

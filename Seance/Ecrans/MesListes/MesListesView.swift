import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Mes listes (EF-16) : ce qui arrive pour les titres surveillés, puis à voir, en cours et terminés.
struct MesListesView: View {
    enum Onglet: String, CaseIterable, Identifiable {
        case aVenir = "À venir"
        case aVoir = "À voir"
        case enCours = "En cours"
        case termines = "Terminés"

        var id: String { rawValue }

        var statut: StatutSuivi? {
            switch self {
            case .aVenir: nil
            case .aVoir: .aVoir
            case .enCours: .enCours
            case .termines: .termine
            }
        }
    }

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    @Query(sort: \Echeance.date) private var echeances: [Echeance]
    @Query private var visionnages: [Visionnage]
    @State private var onglet = Onglet.aVoir

    var body: some View {
        NavigationStack {
            List {
                Picker("Liste", selection: $onglet) {
                    ForEach(Onglet.allCases) { onglet in
                        Text(onglet.rawValue).tag(onglet)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                if onglet == .aVenir {
                    aVenir
                } else if let statut = onglet.statut {
                    liste(statut)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle("Mes listes")
            .destinationsTitres()
            .refreshable { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
        }
    }

    // MARK: À venir

    @ViewBuilder
    private var aVenir: some View {
        let futures = echeances.filter { $0.date >= Calendar.current.startOfDay(for: .now) }
        if futures.isEmpty {
            vide(etat.alertes.enCours
                 ? "Recherche des prochains épisodes et sorties…"
                 : "Rien d'annoncé pour l'instant. Touche la cloche 🔔 sur une fiche pour suivre ses prochains épisodes, ses sorties et ses passages à la télé.")
        }
        ForEach(parJour(futures), id: \.jour) { groupe in
            Section(groupe.libelle) {
                ForEach(groupe.echeances) { echeance in
                    NavigationLink(value: echeance.reference) {
                        HStack(spacing: 12) {
                            ImageDistante(url: ImageTMDB.url(echeance.cheminAffiche, .affiche), coins: 8)
                                .frame(width: 44, height: 66)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(echeance.titre).font(.headline).lineLimit(1)
                                Label(echeance.libelle, systemImage: symbole(echeance.nature))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.accentClair)
                            }
                            Spacer()
                            Text(compteARebours(echeance.date))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.surface, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func parJour(_ echeances: [Echeance]) -> [(jour: Date, libelle: String, echeances: [Echeance])] {
        let calendrier = Calendar.current
        let groupes = Dictionary(grouping: echeances) { calendrier.startOfDay(for: $0.date) }
        return groupes.keys.sorted().map { jour in
            let libelle: String
            if calendrier.isDateInToday(jour) {
                libelle = "Aujourd'hui"
            } else if calendrier.isDateInTomorrow(jour) {
                libelle = "Demain"
            } else {
                libelle = jour.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "fr_CH"))).capitalized
            }
            return (jour, libelle, groupes[jour] ?? [])
        }
    }

    private func compteARebours(_ date: Date) -> String {
        let jours = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch jours {
        case ..<1: return "Aujourd'hui"
        case 1: return "Demain"
        default: return "Dans \(jours) j"
        }
    }

    private func symbole(_ nature: EcheancePrevue.Nature) -> String {
        switch nature {
        case .episode: "play.tv"
        case .saison: "sparkles.tv"
        case .sortie: "film"
        case .tele: "tv"
        }
    }

    // MARK: À voir, en cours, terminés

    @ViewBuilder
    private func liste(_ statut: StatutSuivi) -> some View {
        let titres = suivis.filter { $0.statut == statut }
        if titres.isEmpty {
            switch statut {
            case .aVoir: vide("Rien à voir pour l'instant. Touche « + » sur une fiche pour l'ajouter ici.")
            case .enCours: vide("Aucune série en cours. Coche un épisode sur la fiche d'une série pour la suivre ici.")
            default: vide("Rien ici pour l'instant.")
            }
        }
        ForEach(titres) { suivi in
            NavigationLink(value: suivi.reference) {
                ligne(suivi)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    try? ServiceSoiree(contexte: contexte).retenir(suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
                } label: { Label("Ce soir", systemImage: "moon.stars.fill") }
                    .tint(Theme.accent)
                if statut != .termine {
                    Button { changer(suivi, en: .termine) } label: { Label("Terminé", systemImage: "checkmark") }
                        .tint(.green)
                } else {
                    Button { changer(suivi, en: .aVoir) } label: { Label("À revoir", systemImage: "arrow.uturn.backward") }
                        .tint(.blue)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { retirer(suivi) } label: { Label("Retirer", systemImage: "trash") }
                Button { basculerAlertes(suivi) } label: {
                    Label(suivi.alertesActives ? "Sans alertes" : "Alertes", systemImage: suivi.alertesActives ? "bell.slash" : "bell")
                }
                .tint(.orange)
            }
        }
    }

    private func ligne(_ suivi: Suivi) -> some View {
        HStack(spacing: 12) {
            ImageDistante(url: ImageTMDB.url(suivi.cheminAffiche, .affiche), coins: 8)
                .frame(width: 50, height: 75)
            VStack(alignment: .leading, spacing: 4) {
                Text(suivi.titre).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    Text(suivi.type == .film ? "Film" : "Série")
                    if suivi.type == .serie {
                        let vus = visionnages.filter { $0.tmdbID == suivi.tmdbID && $0.typeBrut == TypeTitre.serie.rawValue }.count
                        if vus > 0 { Text("· \(vus) épisode\(vus > 1 ? "s" : "") vu\(vus > 1 ? "s" : "")") }
                    }
                    if let note = suivi.note {
                        Text("· ta note \(note)/10").foregroundStyle(Theme.accentClair)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let prochaine = echeances.first(where: { $0.tmdbID == suivi.tmdbID && $0.typeBrut == suivi.typeBrut && $0.date >= Calendar.current.startOfDay(for: .now) }) {
                    Label("\(prochaine.libelle) · \(compteARebours(prochaine.date).lowercased())", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentClair)
                }
            }
            Spacer(minLength: 0)
            if suivi.alertesActives {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Alertes activées")
            }
        }
    }

    private func vide(_ texte: String) -> some View {
        Text(texte)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
    }

    private func changer(_ suivi: Suivi, en statut: StatutSuivi) {
        suivi.statut = statut
        try? contexte.save()
    }

    private func retirer(_ suivi: Suivi) {
        contexte.delete(suivi)
        try? contexte.save()
        Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
    }

    private func basculerAlertes(_ suivi: Suivi) {
        suivi.alertesActives.toggle()
        try? contexte.save()
        Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
    }
}

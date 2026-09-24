import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Le programme TV sur la TV (EF-115) : un jour à la fois, choisi dans une rangée de sept ; « En ce moment » et « En
/// soirée » en grandes cartes. Pas de cloche ici : tvOS n'a pas de notifications, et celle qui préviendra l'iPhone
/// attend la synchronisation — en attendant, un passage se prévoit pour la soirée depuis sa fiche.
struct TeleTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @Query private var chaines: [Chaine]
    @Query private var suivis: [Suivi]

    @State private var jourChoisi: DateTMDB?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { horloge in
            let maintenant = horloge.date
            let parJour = Dictionary(grouping: GrilleTele.blocs(diffusions.filter { $0.fin > maintenant })) { GrilleTele.jourAffiche($0, maintenant: maintenant) }
            let jours = parJour.keys.sorted().prefix(7).map { $0 }
            let jour = jourChoisi.flatMap { jours.contains($0) ? $0 : nil } ?? jours.first
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 44) {
                    if jours.isEmpty {
                        VideTV(symbole: "tv", titre: etat.teleEnCours ? "Lecture du programme…" : "Rien à venir",
                               message: chaines.contains(where: \.active) ? "Aucun film ni série reconnu sur tes chaînes pour l'instant."
                                                                          : "Choisis tes chaînes dans Réglages › TV : Séance lira leur programme.")
                    } else {
                        rangeeDeJours(jours, choisi: jour, parJour: parJour, maintenant: maintenant)
                        if let jour, let blocs = parJour[jour] {
                            ForEach(MomentTele.allCases, id: \.self) { moment in
                                let duMoment = blocs.filter { GrilleTele.moment($0, maintenant: maintenant) == moment }.sorted { $0.debut < $1.debut }
                                if !duMoment.isEmpty {
                                    EtagereTV(titre: Self.titre(moment), sousTitre: duMoment.count > 1 ? "\(duMoment.count) programmes" : "1 programme") {
                                        ForEach(duMoment) { bloc in carte(bloc, maintenant: maintenant) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 40)
            }
        }
        .task { await etat.actualiserTele(contexte: contexte) }
    }

    private func rangeeDeJours(_ jours: [DateTMDB], choisi: DateTMDB?, parJour: [DateTMDB: [BlocDiffusion]], maintenant: Date) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 24) {
                ForEach(jours, id: \.self) { jour in
                    Button { jourChoisi = jour } label: {
                        VStack(spacing: 4) {
                            Text(Self.nom(jour, maintenant: maintenant)).font(.system(size: 24, weight: .bold))
                            Text("\(jour.jour)").font(.system(size: 46, weight: .heavy))
                            Text((parJour[jour]?.count ?? 0) > 1 ? "\(parJour[jour]?.count ?? 0) titres" : "1 titre").font(.system(size: 20)).opacity(0.75)
                        }
                        .frame(width: 170, height: 150)
                    }
                    .buttonStyle(BoutonTV(principal: jour == choisi, hauteur: nil))
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    @ViewBuilder
    private func carte(_ bloc: BlocDiffusion, maintenant: Date) -> some View {
        let contenu = CarteLargeTV(surtitre: surtitre(bloc, maintenant: maintenant), titre: bloc.premiere.titreGuide,
                                   detail: detail(bloc), cheminImage: bloc.premiere.cheminFond ?? bloc.premiere.cheminAffiche)
        if let reference = bloc.reference {
            NavigationLink(value: reference) { contenu }.buttonStyle(.card)
        } else {
            // Pas de fiche TMDB : la carte se parcourt, elle ne s'ouvre pas.
            Button {} label: { contenu }.buttonStyle(.card)
        }
    }

    private func surtitre(_ bloc: BlocDiffusion, maintenant: Date) -> String {
        let heure = bloc.debut.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH")))
        let chaine = NomChaineTV.lire(bloc.premiere.chaine, parmi: chaines)
        return bloc.debut <= maintenant ? "EN DIRECT · \(chaine)" : "\(heure) · \(chaine)"
    }

    private func detail(_ bloc: BlocDiffusion) -> String {
        var morceaux = [bloc.estFilm ? "Film" : "Série"]
        if let episodes = bloc.libelleEpisodes { morceaux.append(episodes) }
        let minutes = bloc.dureeMinutes
        morceaux.append(minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min")
        if let reference = bloc.reference, suivis.contains(where: { $0.reference == reference }) { morceaux.append("Dans ta liste") }
        return morceaux.joined(separator: " · ")
    }

    private static func titre(_ moment: MomentTele) -> String {
        switch moment {
        case .enCours: "En ce moment"
        case .soiree: "En soirée"
        case .journee: "Dans la journée"
        case .nuit: "Tard le soir et la nuit"
        }
    }

    private static func nom(_ jour: DateTMDB, maintenant: Date) -> String {
        if jour == GrilleTele.jourTele(maintenant) { return "Auj." }
        if jour == GrilleTele.jourTele(maintenant.addingTimeInterval(86_400)) { return "Demain" }
        return jour.instant(fuseau: .suisse).formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_CH"))).capitalized
    }
}

/// Le nom d'une chaîne : celui que l'utilisateur connaît, sinon l'identifiant du guide sans son suffixe (« W9.fr » → « W9 »).
enum NomChaineTV {
    static func lire(_ identifiant: String, parmi chaines: [Chaine]) -> String {
        if let nom = chaines.first(where: { $0.identifiantGuide == identifiant })?.nom, !nom.isEmpty { return nom }
        return identifiant.split(separator: ".").first.map(String.init) ?? identifiant
    }
}

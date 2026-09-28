import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Regarder › TV sur la TV (8.0, EF-115) : le programme du jour choisi dans la rangée de Regarder, « En ce moment » et
/// « En soirée » en grandes cartes. `moments` limite les sections (Regarder › Tout n'en montre que deux). Pas de cloche :
/// tvOS n'a pas de notifications ; un passage se prévoit pour la soirée depuis sa fiche.
struct SectionsTeleTV: View {
    let jour: DateTMDB
    var moments: [MomentTele] = MomentTele.allCases
    /// Le titre de la première section, quand Regarder › Tout l'annonce autrement : « En ce moment à la TV ».
    var prefixe: String?
    /// Films, séries, ou les deux (8.6) : les pastilles de Regarder › TV.
    var types: Set<TypeTitre> = [.film, .serie]

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @Query private var chaines: [Chaine]
    @Query private var suivis: [Suivi]
    /// « Programme complet » : la journée et la nuit s'ajoutent à « En ce moment » et « Ce soir ».
    @State private var complet = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { horloge in
            let maintenant = horloge.date
            let blocs = GrilleTele.blocs(diffusions.filter { $0.fin > maintenant && types.contains(TypeTitre(rawValue: $0.typeBrut) ?? .film) })
                .filter { GrilleTele.jourAffiche($0, maintenant: maintenant) == jour }
            VStack(alignment: .leading, spacing: 44) {
                if blocs.isEmpty, prefixe == nil {
                    VideTV(symbole: "tv", titre: etat.teleEnCours ? "Lecture du programme…" : "Rien à venir ce jour-là",
                           message: chaines.contains(where: \.active) ? "Aucun film ni série reconnu sur tes chaînes pour ce jour."
                                                                      : "Choisis tes chaînes dans Réglages › TV : Séance lira leur programme.")
                }
                // Maquette 8.0, n° 9 : le direct en grandes cartes, le reste en tuiles d'horaire ; « Programme complet »
                // ajoute la journée et la nuit.
                ForEach(moments.filter { complet || prefixe != nil || [.enCours, .soiree].contains($0) }, id: \.self) { moment in
                    let duMoment = blocs.filter { GrilleTele.moment($0, maintenant: maintenant) == moment }.sorted { $0.debut < $1.debut }
                    if !duMoment.isEmpty {
                        if moment == .enCours || prefixe != nil {
                            EtagereTV(titre: Self.titre(moment, prefixe: prefixe), sousTitre: duMoment.count > 1 ? "\(duMoment.count) programmes" : "1 programme") {
                                ForEach(duMoment) { bloc in carte(bloc, maintenant: maintenant) }
                            }
                        } else {
                            horaires(Self.titre(moment, prefixe: nil), duMoment, lien: moment == .soiree && !complet)
                        }
                    }
                }
            }
        }
        .task { await etat.actualiserTele(contexte: contexte) }
    }

    /// Une rangée de tuiles d'horaire : l'heure, le titre, la chaîne.
    private func horaires(_ titre: String, _ blocs: [BlocDiffusion], lien: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(titre).font(.system(size: 38, weight: .bold))
                Spacer()
                if lien {
                    Button("Programme complet") { complet = true }.buttonStyle(LienTV())
                }
            }
            .padding(.horizontal, MargesTV.bord)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 24) {
                    ForEach(blocs) { bloc in
                        let tuile = HStack(spacing: 18) {
                            Text(bloc.debut.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH"))))
                                .font(.system(size: 28, weight: .heavy).monospacedDigit())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bloc.premiere.titreGuide).font(.system(size: 26, weight: .semibold)).lineLimit(1)
                                Text(NomChaineTV.lire(bloc.premiere.chaine, parmi: chaines)).font(.system(size: 20)).foregroundStyle(Theme.texte2)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(width: 440, height: 96)
                        .background(Theme.surface)
                        if let reference = bloc.reference {
                            NavigationLink(value: reference) { tuile }.buttonStyle(.card)
                                .menuCarteTV(reference, titre: bloc.premiere.titreGuide, cheminAffiche: bloc.premiere.cheminAffiche)
                        } else {
                            Button {} label: { tuile }.buttonStyle(.card)
                        }
                    }
                }
                .padding(.horizontal, MargesTV.bord)
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }

    @ViewBuilder
    private func carte(_ bloc: BlocDiffusion, maintenant: Date) -> some View {
        let contenu = CarteLargeTV(surtitre: surtitre(bloc, maintenant: maintenant), titre: bloc.premiere.titreGuide,
                                   detail: detail(bloc, maintenant: maintenant), cheminImage: bloc.premiere.cheminFond ?? bloc.premiere.cheminAffiche,
                                   lectureEnCoin: bloc.debut <= maintenant, enDirect: bloc.debut <= maintenant)
        if let reference = bloc.reference {
            NavigationLink(value: reference) { contenu }.buttonStyle(.card)
                .menuCarteTV(reference, titre: bloc.premiere.titreGuide, cheminAffiche: bloc.premiere.cheminAffiche)
        } else {
            // Pas de fiche TMDB : la carte se parcourt, elle ne s'ouvre pas.
            Button {} label: { contenu }.buttonStyle(.card)
        }
    }

    private func surtitre(_ bloc: BlocDiffusion, maintenant: Date) -> String {
        let heure = bloc.debut.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH")))
        let chaine = NomChaineTV.lire(bloc.premiere.chaine, parmi: chaines)
        return bloc.debut <= maintenant ? chaine : "\(chaine) · \(heure)"
    }

    private func detail(_ bloc: BlocDiffusion, maintenant: Date) -> String {
        // En direct : ce qu'il reste, comme sur la maquette (« encore 1 h 12 »).
        if bloc.debut <= maintenant {
            let reste = max(Int(bloc.fin.timeIntervalSince(maintenant) / 60), 0)
            return reste >= 60 ? "encore \(reste / 60) h \(String(format: "%02d", reste % 60))" : "encore \(reste) min"
        }
        var morceaux = [bloc.estFilm ? "Film" : "Série"]
        if let episodes = bloc.libelleEpisodes { morceaux.append(episodes) }
        let minutes = bloc.dureeMinutes
        morceaux.append(minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min")
        if let reference = bloc.reference, suivis.contains(where: { $0.reference == reference }) { morceaux.append("Dans ta liste") }
        return morceaux.joined(separator: " · ")
    }

    private static func titre(_ moment: MomentTele, prefixe: String?) -> String {
        let base = switch moment {
        case .enCours: "En ce moment"
        case .soiree: "En soirée"
        case .journee: "Dans la journée"
        case .nuit: "Tard le soir et la nuit"
        }
        return prefixe.map { "\(base) \($0)" } ?? base
    }
}

/// Le nom d'une chaîne : celui que l'utilisateur connaît, sinon l'identifiant du guide sans son suffixe (« W9.fr » → « W9 »).
enum NomChaineTV {
    static func lire(_ identifiant: String, parmi chaines: [Chaine]) -> String {
        if let nom = chaines.first(where: { $0.identifiantGuide == identifiant })?.nom, !nom.isEmpty { return nom }
        return identifiant.split(separator: ".").first.map(String.init) ?? identifiant
    }
}

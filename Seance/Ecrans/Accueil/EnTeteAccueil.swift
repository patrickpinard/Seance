import SeanceDonnees
import SeanceKit
import SwiftUI

/// Une proposition pour ce soir (8.1) : un titre, d'où il vient, et de quoi le lancer.
struct PropositionSoir: Identifiable {
    let reference: ReferenceTitre
    let surtitre: String
    let titre: String
    let detail: String?
    var cheminFond: String?
    var cheminAffiche: String?
    /// Une vidéo du NAS entamée : le bouton dit « Reprendre à … » et la relance là où tu t'es arrêté.
    var reprise: (fichier: FichierNAS, position: PositionLecture)?

    var id: ReferenceTitre { reference }
}

/// La tête de l'accueil (8.1, maquettes « Retenu ») : l'image de la proposition bord à bord, son titre et ses trois
/// boutons — Reprendre ou Regarder, Autre chose, Pas ce soir. Sur un écran large (l'iPad en paysage, le Mac), les
/// nouveautés sont à droite ; ailleurs, l'accueil les montre en carrousel juste dessous.
struct EnTeteAccueil: View {
    let proposition: PropositionSoir
    /// Plus d'une proposition : « Autre chose » a un sens.
    let plusieurs: Bool
    /// Les trois nouveautés du panneau de droite ; vide quand la page est trop étroite pour lui.
    let nouveautes: [TitreResume]
    let ligneNouveaute: (TitreResume) -> String?
    let autreChose: () -> Void
    let toutesLesNouveautes: () -> Void

    @Environment(EtatApp.self) private var etat
    @Environment(\.horizontalSizeClass) private var classe

    /// L'iPad et le Mac : le grand titre, et les boutons côte à côte.
    private var large: Bool { classe == .regular }

    var body: some View {
        let decor = etat.decors.decor(proposition.reference)
        let image = ImageTMDB.url(proposition.cheminFond ?? decor?.fond, .fondGrand) ?? ImageTMDB.url(proposition.cheminAffiche, .fondGrand)
        ZStack(alignment: .bottom) {
            ImageDistante(url: image, coins: 0, symboleVide: "")
                .frame(height: large ? 620 : 500)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    ZStack {
                        LinearGradient(stops: [.init(color: Theme.fond.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                               .init(color: Theme.fond.opacity(0.85), location: 0.72), .init(color: Theme.fond, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                        if large {
                            LinearGradient(colors: [Theme.fond.opacity(0.85), .clear], startPoint: .leading, endPoint: .center)
                        }
                    }
                }
                .accessibilityHidden(true)
            if !nouveautes.isEmpty {
                HStack(alignment: .bottom, spacing: 40) {
                    texte.frame(maxWidth: 600, alignment: .leading)
                    Spacer(minLength: 0)
                    panneau.frame(width: 380)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            } else if large {
                texte.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
            } else {
                texte.padding(.horizontal, 20)
            }
        }
        .task(id: proposition.reference) {
            etat.ou.demander(proposition.reference, client: etat.tmdb)
            await etat.decors.charger([proposition.reference], client: etat.tmdb)
        }
    }

    private var texte: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(proposition.surtitre)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.texte.opacity(0.8))
            Text(proposition.titre)
                .font((large ? Font.largeTitle : Font.title).weight(.heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let detail = proposition.detail {
                Text(detail).font(.subheadline).foregroundStyle(Theme.texte.opacity(0.8))
            }
            if let fraction = proposition.reprise?.position.fraction {
                ProgressView(value: fraction)
                    .tint(Theme.texte)
                    .frame(width: 200)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            boutons.padding(.top, 12)
        }
        .foregroundStyle(Theme.texte)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var boutons: some View {
        if large {
            HStack(spacing: 10) {
                principal.fixedSize(horizontal: true, vertical: false)
                secondaires
            }
        } else {
            VStack(spacing: 8) {
                principal.frame(maxWidth: .infinity)
                HStack(spacing: 8) { secondaires }
            }
        }
    }

    /// « Reprendre à 1:03:12 » pour une vidéo entamée ; sinon le bouton de la fiche (« Regarder sur Netflix », « Lire
    /// sur le NAS », ou le choix entre plusieurs accès) ; sans rien pour le regarder, la fiche.
    @ViewBuilder
    private var principal: some View {
        if let reprise = proposition.reprise {
            ChoixLecture(reference: proposition.reference, titre: proposition.titre, sources: [.nas(reprise.fichier)], style: .compact)
        } else if BoutonLectureCarte.aUneSource(proposition.reference, titre: proposition.titre, etat: etat) {
            BoutonLectureCarte(reference: proposition.reference, titre: proposition.titre, style: .compact)
        } else {
            NavigationLink(value: proposition.reference) {
                Label("Voir la fiche", systemImage: "info.circle")
            }
            .buttonStyle(StyleBoutonPrincipal(pleineLargeur: !large))
        }
    }

    @ViewBuilder
    private var secondaires: some View {
        if plusieurs {
            Button("Autre chose", action: autreChose)
                .buttonStyle(StyleBoutonSecondaire(pleineLargeur: !large))
                .fixedSize(horizontal: large, vertical: false)
        }
        Button("Pas ce soir") {
            withAnimation { PasCeSoir.ecarter(proposition.reference) }
        }
        .buttonStyle(StyleBoutonSecondaire(pleineLargeur: !large))
        .fixedSize(horizontal: large, vertical: false)
        .accessibilityHint("« \(proposition.titre) » ne sera plus proposé avant demain")
    }

    /// Les trois dernières nouveautés, à droite de la proposition (iPad et Mac).
    private var panneau: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nouveautés").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                BoutonToutVoir(action: toutesLesNouveautes)
            }
            ForEach(nouveautes) { titre in
                NavigationLink(value: titre.reference) {
                    HStack(spacing: 12) {
                        ImageDistante(url: ImageTMDB.url(titre.cheminFond ?? titre.cheminAffiche, .fond), coins: 8)
                            .frame(width: 104, height: 58)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titre.titre).font(.headline).lineLimit(1)
                            if let ligne = ligne(titre) {
                                Text(ligne).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Theme.eleve.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .actionsRapides(titre)
                .task(id: titre.reference) { etat.ou.demander(titre.reference, client: etat.tmdb) }
            }
        }
        .foregroundStyle(Theme.texte)
    }

    /// « Nouvel épisode · Disney+ » : ce qui est nouveau, puis où le regarder.
    private func ligne(_ titre: TitreResume) -> String? {
        let ou = etat.ou.badges(titre.reference).first { if case .tele = $0 { false } else { true } }.map(BadgeOu.libelle)
        let morceaux = [ligneNouveaute(titre), ou].compactMap { $0 }
        return morceaux.isEmpty ? nil : morceaux.joined(separator: " · ")
    }
}

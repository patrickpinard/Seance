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
///
/// 8.6 (maquette du 28.09.2026) : les propositions défilent en carrousel — on les fait glisser, « Autre chose » passe à
/// la suivante, des points disent où l'on en est ; un toucher sur l'image ou le titre ouvre la fiche. Le bord de la
/// suivante dépasse à droite sur l'iPhone ; le Mac a deux flèches. Les nouveautés, elles, restent en place.
struct EnTeteAccueil: View {
    let propositions: [PropositionSoir]
    /// La proposition montrée.
    @Binding var rang: Int
    /// Les trois nouveautés du panneau de droite ; vide quand la page est trop étroite pour lui.
    let nouveautes: [TitreResume]
    let ligneNouveaute: (TitreResume) -> String?
    let voirFiche: (ReferenceTitre) -> Void
    let toutesLesNouveautes: () -> Void

    @Environment(EtatApp.self) private var etat
    @Environment(\.horizontalSizeClass) private var classe
    @State private var survol = false

    /// L'iPad et le Mac : le grand titre, et les boutons côte à côte.
    private var large: Bool { classe == .regular }
    private var hauteur: CGFloat { large ? 620 : 500 }
    private var courante: PropositionSoir { propositions[min(max(rang, 0), propositions.count - 1)] }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $rang) {
                ForEach(Array(propositions.enumerated()), id: \.element.id) { index, proposition in
                    page(proposition).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: hauteur)
            .sensoryFeedback(.selection, trigger: rang)
            if !nouveautes.isEmpty {
                panneau.frame(width: 380).padding(.trailing, 32).padding(.bottom, 8)
            }
            #if targetEnvironment(macCatalyst)
            if propositions.count > 1, survol { fleches }
            #endif
        }
        .frame(height: hauteur)
        .onHover { survol = $0 }
        .task(id: propositions.map(\.reference)) {
            for proposition in propositions { etat.ou.demander(proposition.reference, client: etat.tmdb) }
            await etat.decors.charger(propositions.map(\.reference), client: etat.tmdb)
        }
    }

    /// Une proposition : son image bord à bord (un toucher ouvre la fiche), son texte et ses boutons.
    private func page(_ proposition: PropositionSoir) -> some View {
        let decor = etat.decors.decor(proposition.reference)
        let image = ImageTMDB.url(proposition.cheminFond ?? decor?.fond, .fondGrand) ?? ImageTMDB.url(proposition.cheminAffiche, .fondGrand)
        return ZStack(alignment: .bottomLeading) {
            ImageDistante(url: image, coins: 0, symboleVide: "")
                .frame(height: hauteur)
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
                .contentShape(Rectangle())
                .onTapGesture { voirFiche(proposition.reference) }
                .accessibilityHidden(true)
            texte(proposition)
                .frame(maxWidth: large ? (nouveautes.isEmpty ? 700 : 600) : .infinity, alignment: .leading)
                .padding(.horizontal, large ? 32 : 20)
                .padding(.bottom, 8)
        }
    }

    private func texte(_ proposition: PropositionSoir) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Le surtitre et le titre ouvrent la fiche, comme l'image ; « › » le dit.
            Button { voirFiche(proposition.reference) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(proposition.surtitre)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.texte.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(proposition.titre)
                            .font((large ? Font.largeTitle : Font.title).weight(.heavy))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.right").font(.headline.weight(.semibold)).foregroundStyle(Theme.texte.opacity(0.6))
                    }
                    if let detail = proposition.detail {
                        Text(detail).font(.subheadline).foregroundStyle(Theme.texte.opacity(0.8))
                    }
                }
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre la fiche")
            .accessibilityIdentifier("titreProposition")
            if let fraction = proposition.reprise?.position.fraction {
                ProgressView(value: fraction)
                    .tint(Theme.texte)
                    .frame(width: 200)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            boutons(proposition).padding(.top, 12)
            if propositions.count > 1 { points }
        }
        .foregroundStyle(Theme.texte)
        .accessibilityElement(children: .contain)
    }

    /// Où l'on en est : un point par proposition, la montrée allongée.
    private var points: some View {
        HStack(spacing: 6) {
            ForEach(propositions.indices, id: \.self) { index in
                Capsule()
                    .fill(index == rang ? Theme.texte : Theme.texte.opacity(0.35))
                    .frame(width: index == rang ? 18 : 6, height: 6)
            }
        }
        // 44 points de haut : VoiceOver y fait défiler les propositions (balayage vers le haut ou le bas).
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .frame(maxWidth: large ? nil : .infinity, alignment: large ? .leading : .center)
        .animation(.snappy, value: rang)
        .accessibilityElement()
        .accessibilityLabel("Proposition \(rang + 1) sur \(propositions.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: aller(de: 1)
            case .decrement: aller(de: -1)
            @unknown default: break
            }
        }
    }

    /// Sur le Mac, au survol : la précédente et la suivante.
    private var fleches: some View {
        HStack {
            Button { aller(de: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Proposition précédente")
            Spacer()
            Button { aller(de: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Proposition suivante")
        }
        .buttonStyle(StyleBoutonRond())
        .padding(.horizontal, 12)
        .padding(.trailing, nouveautes.isEmpty ? 0 : 400)
        .frame(maxHeight: .infinity)
    }

    private func aller(de pas: Int) {
        guard !propositions.isEmpty else { return }
        withAnimation(.snappy) { rang = (rang + pas + propositions.count) % propositions.count }
    }

    @ViewBuilder
    private func boutons(_ proposition: PropositionSoir) -> some View {
        if large {
            HStack(spacing: 10) {
                principal(proposition).fixedSize(horizontal: true, vertical: false)
                secondaires(proposition)
            }
        } else {
            VStack(spacing: 8) {
                principal(proposition).frame(maxWidth: .infinity)
                HStack(spacing: 8) { secondaires(proposition) }
            }
        }
    }

    /// « Reprendre à 1:03:12 » pour une vidéo entamée ; sinon le bouton de la fiche (« Regarder sur Netflix », « Lire
    /// sur le NAS », ou le choix entre plusieurs accès) ; sans rien pour le regarder, la fiche.
    @ViewBuilder
    private func principal(_ proposition: PropositionSoir) -> some View {
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
    private func secondaires(_ proposition: PropositionSoir) -> some View {
        if propositions.count > 1 {
            Button("Autre chose") { aller(de: 1) }
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

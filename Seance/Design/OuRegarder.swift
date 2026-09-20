import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Le dessin d'une pastille « où regarder » : une icône ou un logo, un texte court. `principale` : celle qui lance
/// tout de suite la lecture, en orange ; les autres restent sobres.
struct PastilleOuRegarder: View {
    var symbole: String?
    var logo: String?
    let texte: String
    var principale = false
    /// Une pastille qui ouvre quelque chose le montre d'une petite flèche.
    var ouvre = false

    var body: some View {
        HStack(spacing: 6) {
            if let logo {
                BadgeOu.logo(logo).frame(width: 20, height: 20)
            } else if let symbole {
                Image(systemName: symbole).font(.caption.weight(.bold))
                    .foregroundStyle(principale ? Color.black : Theme.accentClair)
            }
            Text(texte).font(.caption.weight(.semibold)).lineLimit(1)
            if ouvre {
                Image(systemName: "arrow.up.forward").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(principale ? Color.black : Color.primary)
        .padding(.horizontal, 11)
        .frame(minHeight: 32)
        .background {
            if principale { Capsule().fill(Theme.degradeAccent) } else { Capsule().fill(Theme.surface) }
        }
        .overlay(Capsule().strokeBorder(Theme.trait.opacity(principale ? 0 : 1)))
        .zoneDeToucher()
    }
}

/// Où regarder ce titre, tout de suite et selon ce que tu as : « Lire sur le NAS » lance la vidéo, « Netflix » ouvre
/// la plateforme sur le titre, « TF1 · ce soir à 20:55 » mène au programme TV. C'est la raison d'être de Séance :
/// la soirée, les propositions et la recherche le montrent sans ouvrir la fiche.
struct ActionsOuRegarder: View {
    /// Comment les accès se présentent : toutes les pastilles côte à côte, ou un seul bouton qui choisit
    /// pour toi — le NAS d'abord, puis une plateforme de tes abonnements, puis la chaîne qui le passe.
    enum Presentation {
        case pastilles
        case boutonUnique
    }

    let reference: ReferenceTitre
    let titre: String
    /// Pour une série : l'épisode à regarder, cherché sur le NAS.
    var episode: NumeroEpisode?
    /// Ce que la page sait déjà quand aucune pastille ne s'applique : « À louer ou acheter », « Introuvable ».
    var secours: String?
    var presentation: Presentation = .pastilles

    @Environment(EtatApp.self) private var etat
    @Environment(\.openURL) private var openURL
    @Query private var fichiers: [FichierNAS]

    init(reference: ReferenceTitre, titre: String, episode: NumeroEpisode? = nil, secours: String? = nil,
         presentation: Presentation = .pastilles) {
        self.reference = reference
        self.titre = titre
        self.episode = episode
        self.secours = secours
        self.presentation = presentation
        let id: Int? = reference.tmdbID
        let type = reference.type.rawValue
        _fichiers = Query(filter: #Predicate<FichierNAS> { $0.tmdbID == id && $0.typeBrut == type }, sort: \FichierNAS.chemin)
    }

    /// Le fichier à lire : le film, ou l'épisode à regarder s'il est sur le NAS.
    private var fichier: FichierNAS? {
        guard reference.type == .serie else { return fichiers.first }
        guard let episode else { return nil }
        return fichiers.first { $0.saison == episode.saison && $0.episode == episode.episode }
    }

    var body: some View {
        let badges = etat.ou.badges(reference)
        Group {
            if presentation == .boutonUnique, let principal = badges.first {
                VStack(alignment: .leading, spacing: 8) {
                    boutonPrincipal(principal)
                    // Les autres accès restent dits, en petit : le bouton a choisi, il n'a rien caché.
                    if badges.count > 1 {
                        Text("Aussi : " + badges.dropFirst().map(Self.nom).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                pastilles(badges)
            }
        }
        .task(id: reference) { etat.ou.demander(reference, client: etat.tmdb) }
    }

    /// Le seul bouton de la carte de soirée : il lance ce qui est le plus direct.
    @ViewBuilder
    private func boutonPrincipal(_ badge: EtatOu.Badge) -> some View {
        switch badge {
        case .nas:
            if let fichier {
                BoutonLectureNAS(fichier: fichier, libelle: "Regarder maintenant", grand: true)
            } else {
                PastilleOuRegarder(symbole: "externaldrive.fill", texte: reference.type == .serie ? "Sur ton NAS, en partie" : "Sur ton NAS")
            }
        case .plateforme(let id, let nom, let logo):
            if let lien = LiensPlateformes.lien(plateforme: id, titre: titre) {
                Button { openURL(lien) } label: { EtiquetteGrandBouton(symbole: "play.fill", texte: "Regarder sur \(nom)") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Regarder sur \(nom)")
                    .accessibilityHint("Ouvre \(nom) sur ce titre")
            } else {
                PastilleOuRegarder(logo: logo, texte: nom).accessibilityLabel("Inclus sur \(nom)")
            }
        case .tele(let chaine, let quand):
            Button {
                etat.ongletDemande = .accueil
                etat.programmeTeleDemande = true
            } label: { EtiquetteGrandBouton(symbole: "tv.fill", texte: "\(chaine) · \(quand)") }
                .buttonStyle(.plain)
                .accessibilityLabel("À la TV : \(chaine), \(quand)")
                .accessibilityHint("Ouvre le programme TV")
        }
    }

    /// Le nom court d'un accès, pour la ligne « Aussi : … ».
    private static func nom(_ badge: EtatOu.Badge) -> String {
        switch badge {
        case .nas: "ton NAS"
        case .plateforme(_, let nom, _): nom
        case .tele(let chaine, let quand): "\(chaine) \(quand)"
        }
    }

    @ViewBuilder
    private func pastilles(_ badges: [EtatOu.Badge]) -> some View {
        Flux(espacement: 8) {
            ForEach(badges, id: \.self) { badge in
                switch badge {
                case .nas:
                    if let fichier {
                        BoutonLectureNAS(fichier: fichier, libelle: "Lire sur le NAS", pastille: true)
                    } else {
                        PastilleOuRegarder(symbole: "externaldrive.fill", texte: reference.type == .serie ? "Sur ton NAS, en partie" : "Sur ton NAS")
                    }
                case .plateforme(let id, let nom, let logo):
                    if let lien = LiensPlateformes.lien(plateforme: id, titre: titre) {
                        Button { openURL(lien) } label: { PastilleOuRegarder(logo: logo, texte: nom, ouvre: true) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Regarder sur \(nom)")
                            .accessibilityHint("Ouvre \(nom) sur ce titre")
                    } else {
                        PastilleOuRegarder(logo: logo, texte: nom).accessibilityLabel("Inclus sur \(nom)")
                    }
                case .tele(let chaine, let quand):
                    Button {
                        etat.ongletDemande = .accueil
                        etat.programmeTeleDemande = true
                    } label: {
                        PastilleOuRegarder(symbole: "tv.fill", texte: "\(chaine) · \(quand)")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("À la TV : \(chaine), \(quand)")
                    .accessibilityHint("Ouvre le programme TV")
                }
            }
            if badges.isEmpty, let texte = secoursAffiche {
                Label(texte, systemImage: "cart")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 32)
            }
        }
    }

    /// Rien chez toi : le dire plutôt que de laisser un blanc — mais seulement une fois les plateformes lues.
    private var secoursAffiche: String? {
        if let secours { return secours }
        guard etat.ou.aDesAbonnements, etat.ou.plateformesConnues(reference) else { return nil }
        return "Dans aucun de tes abonnements"
    }
}


/// L'habillage d'un grand bouton d'action, du même dessin que « Regarder maintenant » du NAS.
struct EtiquetteGrandBouton: View {
    let symbole: String
    let texte: String

    var body: some View {
        Label(texte, systemImage: symbole)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(.black)
            .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

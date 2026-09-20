import SeanceDonnees
import SeanceKit
import SwiftUI

/// La grande carte 16/9 d'un titre, dans le format des cartes de « Ce soir à la TV » : l'image en plein cadre, où le
/// regarder en haut à gauche (NAS, plateformes, chaîne), et dessous une ligne orange — ce qui compte (« N° 1 », « Sur ton
/// NAS · 4K », « Sur Netflix ») —, le titre, puis le type, l'année, la durée, la note. Patrick l'a choisie le 20 septembre
/// 2026 comme format unique des étagères : très visible, et de la place pour dire quelque chose.
struct CarteLargeTitre: View {
    let reference: ReferenceTitre?
    let titre: String
    /// Grande image de TMDB ; à défaut, l'affiche, cadrée large.
    var cheminFond: String?
    var cheminAffiche: String?
    /// La ligne orange ; `nil` : où regarder, tel que Séance le sait (« Sur ton NAS », « Netflix », « RTS 1, ce soir à 21:10 »).
    var accroche: String?
    /// « 2023 · 2 h 01 · 82 % ».
    var faits: [String] = []
    var rang: Int?

    @Environment(EtatApp.self) private var etat

    static let largeur: CGFloat = 310

    private var film: Bool { reference?.type != .serie }

    /// Où regarder, en toutes lettres.
    private var ou: String? {
        guard let reference else { return nil }
        let noms = etat.ou.badges(reference).map(BadgeOu.libelle)
        return noms.isEmpty ? nil : noms.joined(separator: " · ")
    }

    private var ligneOrange: String? {
        [accroche, ou].compactMap { $0 }.joined(separator: " · ").nilSiVide
    }

    var body: some View {
        let decor = reference.flatMap { etat.decors.decor($0) }
        let image = ImageTMDB.url(cheminFond ?? decor?.fond, .fond) ?? ImageTMDB.url(cheminAffiche, .fond)
        let duree = decor?.minutes.flatMap { $0 > 0 ? HeuresTele.duree($0) : nil }
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { ImageDistante(url: image, coins: 0) }
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.35),
                                       .init(color: .black.opacity(0.92), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) {
                if let reference { BadgeOu(reference: reference).padding(12) }
            }
            .overlay(alignment: .topTrailing) {
                if let rang {
                    Text("\(rang)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.degradeAccent)
                        .shadow(color: .black.opacity(0.7), radius: 4)
                        .padding(.horizontal, 14).padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if let ligneOrange {
                        Text(ligneOrange)
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Theme.accentClair)
                            .lineLimit(1)
                    }
                    Text(titre).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 7) {
                        PastilleType(film: film)
                        Text((faits + [duree].compactMap { $0 }).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
            .foregroundStyle(.white)
            .surImage()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(([titre, film ? "film" : "série"] + [ligneOrange].compactMap { $0 } + faits).joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            .task(id: reference) {
                guard let reference else { return }
                etat.ou.demander(reference, client: etat.tmdb)
            }
    }
}

extension CarteLargeTitre {
    /// Un titre de TMDB : année, note.
    init(_ resume: TitreResume, accroche: String? = nil, rang: Int? = nil) {
        var faits: [String] = []
        if let annee = resume.date?.annee { faits.append(String(annee)) }
        if resume.nombreVotes > 0 { faits.append("\(resume.pourcentageNote) %") }
        self.init(reference: resume.reference, titre: resume.titre, cheminFond: resume.cheminFond, cheminAffiche: resume.cheminAffiche,
                  accroche: accroche, faits: faits, rang: rang)
    }
}

private extension String {
    var nilSiVide: String? { isEmpty ? nil : self }
}

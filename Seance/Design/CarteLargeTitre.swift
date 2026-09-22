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
    /// Un symbole discret en haut à droite, quand le rang ne s'y trouve pas : la cloche des alertes, l'œil du déjà-vu.
    var symboleCoin: String?
    /// `false` quand l'accroche dit déjà où regarder (« Sur W9 à 18:14 ») : la chaîne ne se répète pas derrière.
    var ouApresAccroche = true
    /// ▶︎ en bas à droite (6.1) : la lecture d'un toucher, quand le titre se lance d'ici.
    var lecture = true

    @Environment(EtatApp.self) private var etat

    static let largeur: CGFloat = 310

    /// La grille des pages en cartes 16/9, la même partout : une colonne sur l'iPhone ; sur l'iPad et le Mac, des cartes de la
    /// taille de celles des étagères (310 points), autant que la fenêtre en contient. Sans ce plafond, une page laissait ses
    /// cartes grossir jusqu'à 520 points et une autre les serrait dans des colonnes d'affiches de 150 : aucun format commun.
    @MainActor static var colonnes: [GridItem] {
        let telephone = UIDevice.current.userInterfaceIdiom == .phone
        return [GridItem(.adaptive(minimum: 290, maximum: telephone ? 520 : 350), spacing: 14, alignment: .top)]
    }

    private var film: Bool { reference?.type != .serie }

    /// Où regarder, en toutes lettres. Deux sources au plus — trois ne tiennent pas sur une ligne, et la carte
    /// coupait le texte au milieu d'un mot ; une seule quand la carte a déjà son accroche.
    private func ou(avecAccroche: Bool) -> String? {
        guard let reference else { return nil }
        let noms = etat.ou.badges(reference).map(BadgeOu.libelle).prefix(avecAccroche ? 1 : 2)
        return noms.isEmpty ? nil : noms.joined(separator: " · ")
    }

    private var ligneOrange: String? {
        [accroche, accroche != nil && !ouApresAccroche ? nil : ou(avecAccroche: accroche != nil)].compactMap { $0 }.joined(separator: " · ").nilSiVide
    }

    var body: some View {
        let decor = reference.flatMap { etat.decors.decor($0) }
        let image = ImageTMDB.url(cheminFond ?? decor?.fond, .fond) ?? ImageTMDB.url(cheminAffiche, .fond)
        let duree = decor?.minutes.flatMap { $0 > 0 ? HeuresTele.duree($0) : nil }
        let avecLecture = lecture && reference.map { BoutonLectureCarte.aUneSource($0, titre: titre, etat: etat) } == true
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
                if let symboleCoin, rang == nil {
                    Image(systemName: symboleCoin)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accentClair)
                        .padding(7)
                        .background(.black.opacity(0.6), in: Circle())
                        .padding(10)
                        .accessibilityHidden(true)
                }
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
                // Le texte laisse la place au ▶︎ en bas à droite.
                .padding(.trailing, avecLecture ? 50 : 0)
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
            // ▶︎ (6.1) : hors de l'élément d'accessibilité de la carte, pour rester un bouton à part — la carte ouvre la
            // fiche, le rond lance la lecture, ou demande où quand le titre est à plusieurs endroits.
            .overlay(alignment: .bottomTrailing) {
                if avecLecture, let reference {
                    BoutonLectureCarte(reference: reference, titre: titre).padding(10)
                }
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

extension CarteLargeTitre {
    /// Un titre de Mes listes : son prochain rendez-vous ou sa note en accroche, ses épisodes vus dans les faits.
    init(suivi: Suivi, rendezVous: String? = nil, episodesVus: Int = 0) {
        var faits: [String] = []
        if suivi.type == .serie, episodesVus > 0 { faits.append(Format.pluriel(episodesVus, "épisode vu", "épisodes vus")) }
        if let note = suivi.note { faits.append("★ \(note)/10") }
        self.init(reference: suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche,
                  accroche: rendezVous, faits: faits, symboleCoin: suivi.alertesActives ? "bell.fill" : nil)
    }

    /// Un fichier du NAS : la qualité en accroche, l'année et le poids dans les faits.
    init(fichier: FichierNAS, nouveau: Bool = false) {
        var accroche: [String] = []
        if nouveau { accroche.append("Nouveau") }
        if let qualite = fichier.qualite { accroche.append(qualite) }
        var faits: [String] = []
        if let annee = fichier.annee { faits.append(String(annee)) }
        if fichier.nombreVotes > 0 { faits.append("\(Int((fichier.noteMoyenne * 10).rounded())) %") }
        self.init(reference: fichier.reference, titre: fichier.titre, cheminFond: fichier.cheminFond,
                  cheminAffiche: fichier.cheminAffiche, accroche: accroche.isEmpty ? nil : accroche.joined(separator: " · "),
                  faits: faits)
    }

    /// Un titre d'une liste nommée : de quoi l'afficher sans réseau.
    init(apercu: ApercuTitre) {
        self.init(reference: apercu.reference, titre: apercu.titre, cheminAffiche: apercu.cheminAffiche)
    }

    /// ★ Un favori : son année et son type.
    init(favori: Favori) {
        self.init(reference: favori.reference, titre: favori.titre, cheminAffiche: favori.cheminAffiche,
                  faits: [favori.annee.map(String.init)].compactMap { $0 }, symboleCoin: "star.fill")
    }

    /// Un rendez-vous d'« À venir » : « Épisode 3 · demain » en accroche.
    init(echeance: Echeance, quand: String? = nil) {
        self.init(reference: echeance.reference, titre: echeance.titre, cheminAffiche: echeance.cheminAffiche,
                  accroche: [echeance.libelle, quand].compactMap { $0 }.joined(separator: " · "))
    }
}

private extension String {
    var nilSiVide: String? { isEmpty ? nil : self }
}

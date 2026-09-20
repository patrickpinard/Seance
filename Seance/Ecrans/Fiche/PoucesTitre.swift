import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// 👍 👎 comme sur Netflix : dire d'un toucher qu'un titre te plaît ou non, **sans l'avoir vu** — la note de 1 à 10,
/// elle, vient après l'avoir regardé. Le pouce levé oriente tes goûts, donc les idées du soir ; le pouce baissé fait
/// en plus sortir le titre de toutes les propositions (Réglages › Prénom et idées permet d'y revenir).
struct PoucesTitre: View {
    let reference: ReferenceTitre
    let titre: String
    let cheminAffiche: String?
    let genres: [Int]
    var acteursIDs: [Int] = []
    var acteurs: [String] = []

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var aimes: [TitreAime]
    @Query private var suivis: [Suivi]

    init(reference: ReferenceTitre, titre: String, cheminAffiche: String?, genres: [Int], acteursIDs: [Int] = [], acteurs: [String] = []) {
        self.reference = reference
        self.titre = titre
        self.cheminAffiche = cheminAffiche
        self.genres = genres
        self.acteursIDs = acteursIDs
        self.acteurs = acteurs
        let id = reference.tmdbID
        let type = reference.type.rawValue
        _aimes = Query(filter: #Predicate<TitreAime> { $0.tmdbID == id && $0.typeBrut == type })
        _suivis = Query(filter: #Predicate<Suivi> { $0.tmdbID == id && $0.typeBrut == type })
    }

    private var aime: Bool { !aimes.isEmpty }
    private var ecarte: Bool { suivis.first?.statut == .exclu }

    var body: some View {
        HStack(spacing: 10) {
            pouce("hand.thumbsup", plein: "hand.thumbsup.fill", nom: aime ? "J'aime ✓" : "J'aime", actif: aime,
                  aide: aime ? "Tu aimes ce titre. Toucher pour retirer ton pouce." : "Ce titre te plaît : Séance te proposera davantage de titres de ce genre.") {
                basculerAime()
            }
            pouce("hand.thumbsdown", plein: "hand.thumbsdown.fill", nom: ecarte ? "Je n'aime pas ✓" : "Je n'aime pas", actif: ecarte,
                  aide: ecarte ? "Tu as écarté ce titre. Toucher pour qu'il puisse de nouveau t'être proposé."
                               : "Je n'aime pas : Séance ne te le proposera plus, et en tient compte pour tes goûts.") {
                basculerEcarte()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private func pouce(_ symbole: String, plein: String, nom: String, actif: Bool, aide: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(nom, systemImage: actif ? plein : symbole)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(actif ? Theme.accentClair : Color.primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(actif ? AnyShapeStyle(Theme.accent.opacity(0.18)) : AnyShapeStyle(Theme.surface), in: Capsule())
                .overlay(Capsule().strokeBorder(actif ? Theme.accent.opacity(0.5) : Theme.trait))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(aide)
        .accessibilityHint(aide)
        .accessibilityAddTraits(actif ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: actif)
    }

    private func basculerAime() {
        let gouts = ServiceGouts(contexte: contexte)
        if aime {
            try? gouts.nePlusAimer(reference)
            etat.confirmer("Pouce retiré", symbole: "hand.thumbsup")
        } else {
            try? gouts.aimer(reference, titre: titre, cheminAffiche: cheminAffiche, genres: genres, acteursIDs: acteursIDs, acteurs: acteurs)
            etat.confirmer("Noté : tes idées en tiendront compte", symbole: "hand.thumbsup.fill")
        }
    }

    private func basculerEcarte() {
        let gouts = ServiceGouts(contexte: contexte)
        if ecarte {
            try? gouts.reproposer(reference)
            etat.confirmer("« \(titre) » pourra de nouveau t'être proposé", symbole: "arrow.uturn.backward")
        } else {
            let avant = suivis.first
            let statutAvant = avant?.statut
            let existait = avant != nil
            try? gouts.jamais(reference, titre: titre, genres: genres, cheminAffiche: cheminAffiche)
            try? ServiceSoiree(contexte: contexte).retirer(reference)
            let reference = reference
            etat.confirmer("Ne te sera plus proposé", symbole: "hand.thumbsdown.fill") { [contexte] in
                AnnulationTitre.restaurer(reference, existait: existait, statut: statutAvant, contexte: contexte)
            }
        }
    }
}

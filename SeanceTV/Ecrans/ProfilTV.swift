import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Le Profil sur la TV (EF-132) : tes dernières notes en affiches, tes acteurs en portraits, tes goûts, et tes chiffres
/// en bas de page, sans les mettre en avant.
struct ProfilTV: View {
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    @Query(sort: \ActeurSuivi.suiviLe, order: .reverse) private var acteurs: [ActeurSuivi]
    @Query(sort: \Interet.libelle) private var interets: [Interet]
    @Query private var visionnages: [Visionnage]
    /// 👍 Tes « J'aime », le plus récent d'abord.
    @Query(sort: \TitreAime.aimeLe, order: .reverse) private var aimes: [TitreAime]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                if notes.isEmpty, acteurs.isEmpty, interets.isEmpty, aimes.isEmpty {
                    VideTV(symbole: "person.crop.circle", titre: "Ton profil se remplira tout seul",
                           message: "Tes notes, tes acteurs et tes goûts arrivent de ton iPhone, et de ce que tu marques vu ici.")
                }
                if !notes.isEmpty {
                    EtagereTV(titre: "Tes dernières notes", sousTitre: "Elles affinent ce que Séance te propose") {
                        ForEach(notes) { suivi in
                            NavigationLink(value: suivi.reference) {
                                CarteLargeTV(surtitre: "★ \(suivi.note ?? 0)/10", titre: suivi.titre, detail: nil,
                                             cheminImage: suivi.cheminAffiche, largeur: CarteLargeTV.largeurGrille, reference: suivi.reference)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                if !aimes.isEmpty {
                    EtagereTV(titre: "👍 Tu aimes", sousTitre: "Tes pouces levés orientent les idées du soir") {
                        ForEach(aimes.prefix(30), id: \.reference) { aime in
                            NavigationLink(value: aime.reference) {
                                CarteLargeTV(surtitre: nil, titre: aime.titre, detail: aime.reference.type == .film ? "Film" : "Série",
                                             cheminImage: aime.cheminAffiche, largeur: CarteLargeTV.largeurGrille, reference: aime.reference)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                if !acteurs.isEmpty {
                    EtagereTV(titre: "Tes acteurs", sousTitre: "Ceux dont tu suis les nouveaux films — choisis-en un pour voir ses films") {
                        ForEach(acteurs, id: \.personneID) { acteur in
                            NavigationLink(value: PersonneTVRef(id: acteur.personneID, nom: acteur.nom)) {
                                AfficheTV(titre: acteur.nom, sousTitre: nil, cheminAffiche: acteur.cheminPortrait)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                if !interets.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Tes goûts").font(.system(size: 38, weight: .bold))
                        Text(interets.map(\.libelle).joined(separator: "  ·  ")).font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.accentClair)
                        Text("Ils se modifient dans Réglages › Tes goûts.").font(.system(size: 24)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, MargesTV.bord)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tes chiffres").font(.system(size: 38, weight: .bold))
                    HStack(spacing: 30) {
                        chiffre("\(filmsVus)", filmsVus > 1 ? "films vus" : "film vu")
                        chiffre("\(episodesVus)", episodesVus > 1 ? "épisodes vus" : "épisode vu")
                        chiffre("\(heures) h", "devant l'écran")
                        chiffre("\(suivis.filter { $0.note != nil }.count)", "titres notés")
                    }
                }
                .padding(.horizontal, MargesTV.bord)
            }
            .padding(.vertical, 40)
        }
    }

    private var notes: [Suivi] { suivis.filter { $0.note != nil }.prefix(20).map { $0 } }
    private var filmsVus: Int { Set(visionnages.filter { $0.type == .film }.map(\.tmdbID)).count }
    private var episodesVus: Int { visionnages.filter { $0.type == .serie && $0.episode != nil }.count }
    private var heures: Int { visionnages.reduce(0) { $0 + $1.dureeMinutes } / 60 }

    private func chiffre(_ valeur: String, _ libelle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(valeur).font(.system(size: 54, weight: .heavy)).foregroundStyle(Theme.accentClair)
            Text(libelle).font(.system(size: 24)).foregroundStyle(.secondary)
        }
        .frame(width: 320, alignment: .leading)
        .padding(28)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

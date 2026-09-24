import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Mes listes sur la TV : les six mêmes boutons que sur l'iPhone (8.0) — à venir, à voir, en cours, terminés, favoris,
/// listes nommées.
struct ListesTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    /// Les rendez-vous de tes titres, à partir d'aujourd'hui.
    @Query private var echeances: [Echeance]
    @Query(sort: \ListePerso.nom) private var listes: [ListePerso]
    @Query private var fichiers: [FichierNAS]
    @Query(sort: \Favori.ajouteLe, order: .reverse) private var favoris: [Favori]

    enum Onglet: String, CaseIterable, Hashable {
        case aVenir = "À venir", aVoir = "À voir", enCours = "En cours", termines = "Terminés", favoris = "Favoris", listes = "Listes"

        /// Les symboles de l'iPhone (`MesListesView.Onglet`).
        var symbole: String {
            switch self {
            case .aVenir: "calendar.badge.clock"
            case .aVoir: "bookmark.fill"
            case .enCours: "play.circle.fill"
            case .termines: "checkmark.circle.fill"
            case .favoris: "star.fill"
            case .listes: "rectangle.stack.fill"
            }
        }

        var statut: StatutSuivi? {
            switch self {
            case .aVoir: .aVoir
            case .enCours: .enCours
            case .termines: .termine
            case .aVenir, .favoris, .listes: nil
            }
        }
    }

    @State private var onglet = Onglet.aVoir

    init() {
        let jour = Calendar.current.startOfDay(for: .now)
        _echeances = Query(filter: #Predicate<Echeance> { $0.date >= jour }, sort: \Echeance.date)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 44) {
                if suivis.isEmpty, listes.isEmpty {
                    VideTV(symbole: "bookmark", titre: "Tes listes sont vides sur cette TV",
                           message: "Elles arrivent de ton iPhone, de ton iPad et de ton Mac. Tu peux aussi garder un titre « à voir » depuis sa fiche, ici même.")
                } else {
                    // Maquette 8.0, n° 12 : les six boutons de l'iPhone en tuiles, l'icône au-dessus du nom ; le choisi en blanc.
                    HStack(spacing: 20) {
                        ForEach(Onglet.allCases, id: \.self) { choix in
                            Button { onglet = choix } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: choix.symbole).font(.system(size: 30, weight: .semibold))
                                    Text(choix.rawValue).font(.system(size: 24, weight: .semibold))
                                }
                                .frame(width: 190, height: 116)
                            }
                            .buttonStyle(BoutonTV(principal: onglet == choix, hauteur: nil))
                        }
                    }
                    .padding(.horizontal, MargesTV.bord)
                    .focusSection()
                    if onglet == .aVenir {
                        aVenir
                    } else if onglet == .favoris {
                        grilleFavoris
                    } else if onglet == .listes {
                        if listes.allSatisfy(\.titres.isEmpty) {
                            VideTV(symbole: "rectangle.stack", titre: "Aucune liste",
                                   message: "Crée tes listes sur ton iPhone — « Soirées entre amis », « À voir en famille » — elles arriveront ici.")
                        }
                        ForEach(listes.filter { !$0.titres.isEmpty }) { liste in
                            EtagereTV(titre: liste.nom, sousTitre: liste.titres.count > 1 ? "\(liste.titres.count) titres" : "1 titre") {
                                ForEach(liste.apercus, id: \.reference) { apercu in
                                    NavigationLink(value: apercu.reference) {
                                        CarteLargeTV(surtitre: nil, titre: apercu.titre, detail: nil, cheminImage: apercu.cheminAffiche,
                                                     marque: marque(apercu.reference), reference: apercu.reference)
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                        }
                    } else if let statut = onglet.statut {
                        grille(statut)
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .task { await etat.actualiserAVenir(contexte: contexte) }
    }

    /// Ce qui arrive pour tes titres : nouvel épisode, sortie, passage à la TV. Calculé sur la TV même, faute
    /// de pouvoir venir de l'iPhone : les échéances ne voyagent pas dans la synchronisation, ce sont des données
    /// reconstruites.
    @ViewBuilder
    private var aVenir: some View {
        if echeances.isEmpty {
            VideTV(symbole: "calendar.badge.clock", titre: "Rien de prévu pour l'instant",
                   message: "Les sorties, les nouveaux épisodes et les passages à la TV de tes titres apparaîtront ici.")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(CarteLargeTV.largeurGrille), spacing: 40, alignment: .top), count: 3), spacing: 50) {
                ForEach(echeances) { echeance in
                    NavigationLink(value: echeance.reference) {
                        CarteLargeTV(surtitre: echeance.libelle, titre: echeance.titre, detail: nil,
                                     cheminImage: echeance.cheminAffiche, marque: marque(echeance.reference),
                                     largeur: CarteLargeTV.largeurGrille, reference: echeance.reference)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 20)
            .focusSection()
        }
    }

    /// Une grille plutôt qu'une rangée : une liste compte parfois des dizaines de titres.
    @ViewBuilder
    private func grille(_ statut: StatutSuivi) -> some View {
        let titres = suivis.filter { $0.statut == statut && !$0.masque }
        if titres.isEmpty {
            VideTV(symbole: onglet == .aVoir ? "bookmark" : onglet == .enCours ? "play.circle" : "checkmark.circle",
                   titre: onglet == .aVoir ? "Rien à voir pour l'instant" : onglet == .enCours ? "Aucune série en cours" : "Rien de terminé",
                   message: onglet == .aVoir ? "Garde un titre depuis sa fiche : il se range ici."
                          : onglet == .enCours ? "Coche un épisode sur la fiche d'une série : elle se range ici."
                          : "Un film vu, une série finie : ils se rangent ici, avec ta note.")
        } else {
            Text(titres.count > 1 ? "\(titres.count) titres" : "1 titre").font(.system(size: 34, weight: .bold))
                .padding(.horizontal, MargesTV.bord)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(390), spacing: 34, alignment: .top), count: 4), spacing: 44) {
                ForEach(titres) { suivi in
                    NavigationLink(value: suivi.reference) {
                        CarteLargeTV(surtitre: suivi.note.map { "★ \($0)/10" }, titre: suivi.titre,
                                     detail: suivi.type == .film ? "Film" : "Série", cheminImage: suivi.cheminAffiche,
                                     largeur: 390, reference: suivi.reference)
                    }
                    .buttonStyle(.card)
                    .menuCarteTV(suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 20)
            .focusSection()
        }
    }

    @ViewBuilder
    private var grilleFavoris: some View {
        if favoris.isEmpty {
            VideTV(symbole: "star", titre: "Aucun favori",
                   message: "Tes incontournables, vus ou non : sur ton iPhone, ouvre une fiche, puis « Plus » › « Ajouter à mes favoris ».")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(CarteLargeTV.largeurGrille), spacing: 40, alignment: .top), count: 3), spacing: 50) {
                ForEach(favoris) { favori in
                    NavigationLink(value: favori.reference) {
                        CarteLargeTV(surtitre: nil, titre: favori.titre, detail: favori.type == .film ? "Film" : "Série",
                                     cheminImage: favori.cheminAffiche, marque: marque(favori.reference),
                                     largeur: CarteLargeTV.largeurGrille, reference: favori.reference)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 20)
            .focusSection()
        }
    }

    private func marque(_ reference: ReferenceTitre) -> String? {
        fichiers.contains { $0.reference == reference } ? "externaldrive.fill" : nil
    }
}

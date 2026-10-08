import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Mes listes sur la TV : les trois mêmes boutons que sur l'iPhone (8.11) — à voir, en cours, à venir.
struct ListesTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    /// Les rendez-vous de tes titres, à partir d'aujourd'hui.
    @Query private var echeances: [Echeance]
    @Query private var fichiers: [FichierNAS]

    enum Onglet: String, CaseIterable, Hashable {
        case aVoir = "À voir", enCours = "En cours", aVenir = "À venir"

        /// Les symboles de l'iPhone (`MesListesView.Onglet`).
        var symbole: String {
            switch self {
            case .aVenir: "calendar.badge.clock"
            case .aVoir: "bookmark.fill"
            case .enCours: "play.circle.fill"
            }
        }

        var statut: StatutSuivi? {
            switch self {
            case .aVoir: .aVoir
            case .enCours: .enCours
            case .aVenir: nil
            }
        }
    }

    @State private var onglet = Onglet.aVoir
    /// 8.7, comme sur l'iPhone : le tri, « Regardable ce soir », cartes ou liste.
    @AppStorage("listes.tri") private var triBrut = TriListe.ajout.rawValue
    @AppStorage("listes.ceSoirSeulement") private var ceSoirSeulement = false
    @AppStorage(VueTitresTV.cle) private var enListe = false
    /// La durée d'un film ou d'un épisode, lue sur TMDB seulement pour le tri « Plus court d'abord ».
    @State private var durees: [ReferenceTitre: Int] = [:]

    private var tri: TriListe { TriListe(rawValue: triBrut) ?? .ajout }

    init() {
        let jour = Calendar.current.startOfDay(for: .now)
        _echeances = Query(filter: #Predicate<Echeance> { $0.date >= jour }, sort: \Echeance.date)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 44) {
                if suivis.isEmpty {
                    VideTV(symbole: "bookmark", titre: "Tes listes sont vides sur cette TV",
                           message: "Elles arrivent de ton iPhone, de ton iPad et de ton Mac. Tu peux aussi garder un titre « à voir » depuis sa fiche, ici même.")
                } else {
                    // Maquette 8.0, n° 12 : les boutons de l'iPhone en tuiles, l'icône au-dessus du nom ; le choisi en blanc.
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
                    // 8.11 : trois tuiles n'occupent plus toute la largeur ; la zone de focus, si — sinon, en descendant du
                    // menu du haut, la télécommande passait par-dessus les onglets.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusSection()
                    if onglet == .aVenir {
                        aVenir
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

    /// Une grille plutôt qu'une rangée : une liste compte parfois des dizaines de titres. 8.7 : ou une liste, triée, et
    /// « Regardable ce soir » — les mêmes commandes que sur l'iPhone.
    @ViewBuilder
    private func grille(_ statut: StatutSuivi) -> some View {
        let tous = suivis.filter { $0.statut == statut && !$0.masque }
        let titres = affiches(tous, statut: statut)
        if tous.isEmpty {
            VideTV(symbole: onglet == .aVoir ? "bookmark" : "play.circle",
                   titre: onglet == .aVoir ? "Rien à voir pour l'instant" : "Aucune série en cours",
                   message: onglet == .aVoir ? "Garde un titre depuis sa fiche : il se range ici."
                          : "Coche un épisode sur la fiche d'une série : elle se range ici.")
        } else {
            // 8.9 (bilan de l'Apple TV) : les commandes à gauche, sous les onglets — à droite, la télécommande arrivait sur
            // « Grille » et le filtre restait à rattraper —, le nombre de titres au bout.
            HStack(spacing: 20) {
                Button("Regardable ce soir") { ceSoirSeulement.toggle() }
                    .buttonStyle(BoutonTV(principal: ceSoirSeulement, hauteur: 56))
                    .accessibilityAddTraits(ceSoirSeulement ? .isSelected : [])
                Menu {
                    Picker("Trier", selection: $triBrut) {
                        ForEach(TriListe.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                    }
                } label: {
                    Label(tri.rawValue, systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(BoutonTV(hauteur: 56))
                Button { enListe = false } label: { Image(systemName: "square.grid.2x2") }
                    .buttonStyle(BoutonRondTV(choisi: !enListe))
                    .accessibilityLabel("Grille")
                Button { enListe = true } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(BoutonRondTV(choisi: enListe))
                    .accessibilityLabel("Liste")
                Spacer()
                Text(titres.count > 1 ? "\(titres.count) titres" : "\(titres.count) titre").font(.system(size: 34, weight: .bold))
            }
            .padding(.horizontal, MargesTV.bord)
            .focusSection()
            .task(id: tri == .plusCourt ? tous.map(\.reference) : []) {
                guard tri == .plusCourt else { return }
                await chargerDurees(tous.map(\.reference))
            }
            .task(id: ceSoirSeulement ? tous.map(\.reference) : []) {
                guard ceSoirSeulement else { return }
                for suivi in tous { etat.ou.demander(suivi.reference, client: etat.tmdb) }
            }
            if titres.isEmpty {
                VideTV(symbole: "moon.stars", titre: "Rien de regardable ce soir",
                       message: "Aucun de ces titres n'est sur ton NAS, dans tes abonnements ou à la TV ce soir.")
            } else if enListe {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(titres) { suivi in
                        NavigationLink(value: suivi.reference) {
                            HStack(spacing: 28) {
                                ImageTV(url: ImageTMDB.url(suivi.cheminAffiche, .affiche), symboleVide: "film")
                                    .frame(width: 90, height: 135)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(suivi.titre).font(.system(size: 32, weight: .semibold)).lineLimit(1)
                                    Text([suivi.type == .film ? "Film" : "Série", suivi.note.map { "★ \($0)/10" },
                                          durees[suivi.reference].map { $0 >= 60 ? "\($0 / 60) h \(String(format: "%02d", $0 % 60))" : "\($0) min" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 24)).foregroundStyle(Theme.texte2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                        }
                        .buttonStyle(LigneTV())
                        .menuCarteTV(suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
                    }
                }
                .padding(.horizontal, MargesTV.bord)
                .focusSection()
            } else {
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
    }

    /// Le tri choisi, puis « Regardable ce soir » : sur le NAS, dans tes abonnements ou à la TV ce soir.
    private func affiches(_ tous: [Suivi], statut: StatutSuivi) -> [Suivi] {
        let parReference = Dictionary(tous.map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
        let ordonnes = tri.trier(tous.map {
            TriListe.Element(reference: $0.reference, titre: $0.titre, ajouteLe: $0.ajouteLe, dureeMinutes: durees[$0.reference])
        }).compactMap { parReference[$0.reference] }
        guard ceSoirSeulement else { return ordonnes }
        return ordonnes.filter { etat.ou.badge($0.reference) != nil }
    }

    /// Les durées manquantes, six fiches à la fois.
    private func chargerDurees(_ references: [ReferenceTitre]) async {
        guard let client = etat.tmdb else { return }
        let manquantes = references.filter { durees[$0] == nil }
        for lot in stride(from: 0, to: manquantes.count, by: 6).map({ Array(manquantes[$0..<min($0 + 6, manquantes.count)]) }) {
            let lues = await withTaskGroup(of: (ReferenceTitre, Int?).self) { groupe in
                for reference in lot {
                    groupe.addTask {
                        switch reference.type {
                        case .film: (reference, (try? await client.film(reference.tmdbID, complements: []))?.dureeMinutes)
                        case .serie: (reference, (try? await client.serie(reference.tmdbID))?.dureesEpisode.first)
                        }
                    }
                }
                var resultat: [ReferenceTitre: Int] = [:]
                for await (reference, duree) in groupe { if let duree { resultat[reference] = duree } }
                return resultat
            }
            durees.merge(lues) { _, nouvelle in nouvelle }
        }
    }

    private func marque(_ reference: ReferenceTitre) -> String? {
        fichiers.contains { $0.reference == reference } ? "externaldrive.fill" : nil
    }
}

/// Cartes ou liste, sur la TV (8.7) : le choix est gardé d'une page à l'autre, comme sur l'iPhone.
enum VueTitresTV {
    static let cle = "titres.enListe"
}

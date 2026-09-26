import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Une personne ouverte depuis le casting d'une fiche : par valeur, comme tout le reste.
struct PersonneTVRef: Hashable {
    let id: Int
    let nom: String
}

/// La fiche d'un acteur ou d'un réalisateur sur la TV (EF-30 à EF-33) : portrait, biographie, « 12 films vus sur 38 »,
/// ses films et ses séries en étagères — chaque affiche ouvre sa fiche —, et « Suivre » pour être prévenu de ses
/// prochains films (l'alerte part de l'iPhone, qui la reçoit par la synchronisation).
struct PersonneTV: View {
    let personne: PersonneTVRef

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var suivis: [Suivi]
    @Query private var visionnages: [Visionnage]
    @Query private var acteursSuivis: [ActeurSuivi]

    @State private var fiche: FichePersonne?
    @State private var filmographie: Filmographie?
    @State private var erreur: String?
    @State private var bioComplete = false

    private var suivi: Bool { acteursSuivis.contains { $0.personneID == personne.id } }

    /// Vu : un visionnage, ou un titre terminé.
    private var vus: Set<ReferenceTitre> {
        Set(visionnages.map { ReferenceTitre(type: $0.type, tmdbID: $0.tmdbID) })
            .union(suivis.filter { $0.statut == .termine }.map(\.reference))
    }

    private var realisateur: Bool { fiche?.domaine == "Directing" }

    private var credits: [CreditPersonne] {
        guard let filmographie else { return [] }
        return AnalyseFilmographie.significatifs(realisateur ? filmographie.realisations : filmographie.roles)
    }

    /// Les plus connus d'abord : c'est ce qu'on cherche devant la télévision.
    private func titres(_ type: TypeTitre) -> [CreditPersonne] {
        var dejaLa = Set<ReferenceTitre>()
        return credits.filter { $0.type == type && $0.cheminAffiche != nil && dejaLa.insert($0.reference).inserted }
            .sorted { ($0.nombreVotes ?? 0) > ($1.nombreVotes ?? 0) }
    }

    /// Maquette 8.0, n° 15 : Films · Séries · Regardables ce soir.
    enum Filtre: String, CaseIterable { case films = "Films", series = "Séries", regardables = "Regardables ce soir" }
    @State private var filtre = Filtre.films

    var body: some View {
        // Maquette 8.0, n° 15 : la personne à gauche — portrait rond, nom, « Suivre » —, sa filmographie en affiches à droite.
        HStack(alignment: .top, spacing: 60) {
            entete
                .frame(width: 440)
                .focusSection()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 14) {
                        ForEach(Filtre.allCases, id: \.self) { choix in
                            Button(choix.rawValue) { filtre = choix }
                                .buttonStyle(BoutonTV(principal: filtre == choix, hauteur: 56))
                        }
                    }
                    .focusSection()
                    if let erreur {
                        VideTV(symbole: "wifi.exclamationmark", titre: "Fiche indisponible", message: erreur)
                    }
                    let liste = affichees
                    if liste.isEmpty, filmographie != nil {
                        Text(filtre == .regardables ? "Rien de sa filmographie sur ton NAS ni sur tes plateformes." : "Rien ici.")
                            .font(.system(size: 26)).foregroundStyle(Theme.texte2)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(AfficheTV.largeur), spacing: 34, alignment: .top), count: 4), spacing: 40) {
                        ForEach(liste.prefix(60), id: \.reference) { credit in
                            NavigationLink(value: credit.reference) {
                                AfficheTV(titre: credit.titre, sousTitre: credit.date.map { String($0.annee) }, cheminAffiche: credit.cheminAffiche)
                            }
                            .buttonStyle(.card)
                            .menuCarteTV(credit.reference, titre: credit.titre, cheminAffiche: credit.cheminAffiche)
                        }
                    }
                    .focusSection()
                }
                .padding(.vertical, 30)
                .padding(.trailing, MargesTV.bord)
            }
            .scrollClipDisabled()
        }
        .padding(.leading, MargesTV.bord)
        .padding(.top, 40)
        .background(Theme.fond.ignoresSafeArea())
        .task(id: personne.id) { await charger() }
    }

    private var affichees: [CreditPersonne] {
        switch filtre {
        case .films: return titres(.film)
        case .series: return titres(.serie)
        case .regardables:
            return (titres(.film) + titres(.serie)).filter { credit in
                etat.ou.badges(credit.reference).contains { if case .tele = $0 { false } else { true } }
            }
        }
    }

    private var entete: some View {
        VStack(spacing: 22) {
            ImageTV(url: ImageTMDB.url(fiche?.cheminPortrait, .afficheGrande), symboleVide: "person.fill")
                .frame(width: 300, height: 300)
                .clipShape(Circle())
            VStack(spacing: 8) {
                Text(fiche?.nom ?? personne.nom).font(.system(size: 48, weight: .heavy)).multilineTextAlignment(.center).lineLimit(2)
                Text(faits).font(.system(size: 24)).foregroundStyle(Theme.texte2).multilineTextAlignment(.center)
            }
            // 8.1 (demande de Patrick) : un seul bouton. Un clic suit ou ne suit plus ; l'appui long ouvre les choix, comme
            // sur les cartes.
            Button { basculerSuivi() } label: {
                Label(suivi ? "Suivi" : "Suivre", systemImage: suivi ? "bell.fill" : "bell").frame(maxWidth: .infinity)
            }
            .buttonStyle(BoutonTV(principal: !suivi))
            .accessibilityHint("Appui long : plus de choix")
            .contextMenu {
                Button { basculerSuivi() } label: {
                    Label(suivi ? "Ne plus suivre" : "Suivre et être prévenu", systemImage: suivi ? "bell.slash" : "bell")
                }
                Section("Afficher") {
                    ForEach(Filtre.allCases, id: \.self) { choix in
                        Button { filtre = choix } label: {
                            Label(choix.rawValue, systemImage: filtre == choix ? "checkmark" : Self.symbole(choix))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static func symbole(_ filtre: Filtre) -> String {
        switch filtre {
        case .films: "film"
        case .series: "tv"
        case .regardables: "play.circle"
        }
    }

    /// « Acteur · 52 ans · 12 films vus sur 38 ».
    private var faits: String {
        var faits: [String] = []
        if let domaine = fiche?.domaine { faits.append(domaine == "Directing" ? "Réalisateur" : domaine == "Acting" ? "Acteur" : domaine) }
        if let age = fiche?.age(aujourdhui: DateTMDB(.now)) { faits.append(fiche?.dateDeces == nil ? "\(age) ans" : "mort à \(age) ans") }
        if filmographie != nil {
            let compte = AnalyseFilmographie.compte(credits, type: .film, vus: vus, aujourdhui: DateTMDB(.now))
            if compte.total > 0 { faits.append("\(compte.vus) film\(compte.vus > 1 ? "s" : "") vu\(compte.vus > 1 ? "s" : "") sur \(compte.total)") }
        }
        return faits.joined(separator: " · ")
    }

    private func charger() async {
        guard let client = etat.tmdb else { erreur = "Il faut d'abord la clé TMDB : Réglages › TMDB."; return }
        do {
            async let lue = client.personne(personne.id)
            async let roles = client.filmographie(personne: personne.id)
            fiche = try await lue
            filmographie = try await roles
            // « Regardables ce soir » : où regarder chacun, demandé d'avance pour les plus connus.
            for credit in (titres(.film) + titres(.serie)).prefix(40) { etat.ou.demander(credit.reference, client: client) }
        } catch {
            erreur = "TMDB ne répond pas. Vérifie la connexion de l'Apple TV."
        }
    }

    private func basculerSuivi() {
        let service = ServiceActeurs(contexte: contexte)
        if suivi {
            try? service.nePlusSuivre(personne.id)
            etat.dire("Tu ne suis plus \(fiche?.nom ?? personne.nom)")
        } else {
            try? service.suivre(personneID: personne.id, nom: fiche?.nom ?? personne.nom, cheminPortrait: fiche?.cheminPortrait)
            etat.dire("\(fiche?.nom ?? personne.nom) : suivi. Ton iPhone te préviendra de ses prochains films.")
        }
    }
}

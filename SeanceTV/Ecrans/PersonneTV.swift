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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                entete
                if let erreur {
                    VideTV(symbole: "wifi.exclamationmark", titre: "Fiche indisponible", message: erreur)
                }
                etagere("Films", .film)
                etagere("Séries", .serie)
            }
            .padding(.vertical, 60)
        }
        .background(Theme.fond.ignoresSafeArea())
        .task(id: personne.id) { await charger() }
    }

    private var entete: some View {
        HStack(alignment: .top, spacing: 50) {
            ImageTV(url: ImageTMDB.url(fiche?.cheminPortrait, .afficheGrande), symboleVide: "person.fill")
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(width: 300)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(alignment: .leading, spacing: 18) {
                Text(fiche?.nom ?? personne.nom).font(.system(size: 68, weight: .heavy)).lineLimit(2)
                Text(faits).font(.system(size: 28, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 28) {
                    Button { basculerSuivi() } label: {
                        Label(suivi ? "Suivi" : "Suivre", systemImage: suivi ? "bell.fill" : "bell")
                    }
                    .buttonStyle(BoutonTV(principal: !suivi))
                    if let bio = fiche?.biographie, bio.count > 420 {
                        Button { bioComplete.toggle() } label: { Text(bioComplete ? "Réduire" : "Lire la biographie") }
                            .buttonStyle(BoutonTV())
                    }
                }
                .focusSection()
                if suivi {
                    Text("Ton iPhone te préviendra de ses prochains films.").font(.system(size: 24)).foregroundStyle(Theme.accentClair)
                }
                if let bio = fiche?.biographie, !bio.isEmpty {
                    Text(bio).font(.system(size: 27)).foregroundStyle(.white.opacity(0.85)).lineSpacing(5)
                        .lineLimit(bioComplete ? nil : 6)
                        .frame(maxWidth: 1200, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, MargesTV.bord)
    }

    /// « Acteur · 52 ans · né à Beyrouth · 12 films vus sur 38 ».
    private var faits: String {
        var faits: [String] = []
        if let domaine = fiche?.domaine { faits.append(domaine == "Directing" ? "Réalisation" : domaine == "Acting" ? "Interprétation" : domaine) }
        if let age = fiche?.age(aujourdhui: DateTMDB(.now)) { faits.append(fiche?.dateDeces == nil ? "\(age) ans" : "mort à \(age) ans") }
        if let lieu = fiche?.lieuNaissance, !lieu.isEmpty { faits.append(lieu) }
        if filmographie != nil {
            let compte = AnalyseFilmographie.compte(credits, type: .film, vus: vus, aujourdhui: DateTMDB(.now))
            if compte.total > 0 { faits.append("\(compte.vus) film\(compte.vus > 1 ? "s" : "") vu\(compte.vus > 1 ? "s" : "") sur \(compte.total)") }
        }
        return faits.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private func etagere(_ nom: String, _ type: TypeTitre) -> some View {
        let liste = titres(type)
        if !liste.isEmpty {
            EtagereTV(titre: "\(nom) · \(liste.count)", sousTitre: realisateur ? "Réalisés" : "Les plus connus d'abord") {
                ForEach(liste.prefix(40), id: \.reference) { credit in
                    NavigationLink(value: credit.reference) {
                        CarteLargeTV(surtitre: nil, titre: credit.titre,
                                     detail: [credit.date.map { String($0.annee) }, realisateur ? nil : credit.personnage].compactMap { $0 }.joined(separator: " · "),
                                     cheminImage: credit.cheminAffiche, marque: vus.contains(credit.reference) ? "checkmark" : nil,
                                     largeur: CarteLargeTV.largeurGrille)
                    }
                    .buttonStyle(.card)
                }
            }
        }
    }

    private func charger() async {
        guard let client = etat.tmdb else { erreur = "Il faut d'abord la clé TMDB : Réglages › TMDB."; return }
        do {
            async let lue = client.personne(personne.id)
            async let roles = client.filmographie(personne: personne.id)
            fiche = try await lue
            filmographie = try await roles
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

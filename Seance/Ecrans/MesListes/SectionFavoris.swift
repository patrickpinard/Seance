import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// ★ Mes favoris (EF-166) : les titres qu'on garde en mémoire, vus ou non, à part de « À voir » et de « Ce soir ».
/// Chaque affiche porte son badge « où regarder » ; le bouton du haut envoie la liste à qui on veut (EF-167).
struct SectionFavoris: View {
    var recherche = ""

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Favori.ajouteLe, order: .reverse) private var favoris: [Favori]
    @AppStorage(Prenom.cle) private var prenomBrut = ""

    private var montres: [Favori] {
        let texte = recherche.trimmingCharacters(in: .whitespaces)
        guard !texte.isEmpty else { return favoris }
        return favoris.filter { $0.titre.localizedCaseInsensitiveContains(texte) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if favoris.isEmpty {
                EtatVide(symbole: "star", titre: "Aucun favori",
                         message: "Tes incontournables, vus ou non : ouvre une fiche, puis « Plus » › « Ajouter à mes favoris ». Tu pourras envoyer la liste à ta famille.")
            } else {
                HStack {
                    Text(Format.pluriel(montres.count, "favori", "favoris"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ShareLink(item: texteAPartager) {
                        Label("Partager ma liste", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .zoneDeToucher()
                }
                LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
                    ForEach(montres) { favori in
                        NavigationLink(value: favori.reference) {
                            CarteLargeTitre(favori: favori)
                        }
                        .buttonStyle(.plain)
                        // Glisser, comme les cartes des autres listes (8.7) ; l'appui long dit la même chose.
                        .glisserPourRetirer("Retirer") { retirer(favori) }
                        .contextMenu {
                            Button(role: .destructive) { retirer(favori) } label: {
                                Label("Retirer de mes favoris", systemImage: "star.slash")
                            }
                        }
                    }
                }
            }
        }
        .task(id: montres.map(\.reference)) { await etat.decors.charger(montres.map(\.reference), client: etat.tmdb) }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private var texteAPartager: String {
        (try? ServiceFavoris(contexte: contexte).texteAPartager(prenom: Prenom.lire(prenomBrut))) ?? ""
    }

    private func retirer(_ favori: Favori) {
        let reference = favori.reference
        let titre = favori.titre
        let affiche = favori.cheminAffiche
        let annee = favori.annee
        try? ServiceFavoris(contexte: contexte).retirer(reference)
        etat.confirmer("Retiré de tes favoris", symbole: "star.slash") { [contexte] in
            _ = try? ServiceFavoris(contexte: contexte).basculer(reference, titre: titre, cheminAffiche: affiche, annee: annee)
        }
    }
}

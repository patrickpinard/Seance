#if DEBUG
import SeanceKit
import SwiftUI
import WidgetKit

/// Les vues des widgets aux tailles d'un iPhone, pour les relire sur des captures (`SEANCE_APERCU_WIDGETS=1`).
struct ApercuWidgetsView: View {
    @State private var soiree = EntreeSoiree.exemple
    @State private var episodes = EntreeEpisodes.exemple
    @State private var aVenir = EntreeAVenir.exemple

    static var actif: Bool {
        ProcessInfo.processInfo.environment["SEANCE_APERCU_WIDGETS"] != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                groupe("Écran d'accueil")
                HStack(spacing: 16) {
                    ecran(VueSoiree(entree: soiree, famille: .systemSmall), largeur: 170, hauteur: 170)
                    ecran(VueEpisodes(entree: episodes, famille: .systemSmall), largeur: 170, hauteur: 170)
                }
                ecran(VueEpisodes(entree: episodes, famille: .systemMedium), largeur: 356, hauteur: 170)
                ecran(VueSoiree(entree: soiree, famille: .systemMedium), largeur: 356, hauteur: 170)
                HStack(spacing: 16) {
                    ecran(VueAVenir(entree: aVenir, famille: .systemSmall), largeur: 170, hauteur: 170)
                    ecran(VueSoiree(entree: EntreeSoiree(date: .now, titres: []), famille: .systemSmall), largeur: 170, hauteur: 170)
                }
                ecran(VueAVenir(entree: aVenir, famille: .systemMedium), largeur: 356, hauteur: 170)
                ecran(VueAVenir(entree: aVenir, famille: .systemLarge), largeur: 356, hauteur: 376)
                groupe("Écran verrouillé")
                HStack(spacing: 12) {
                    verrouille(VueEpisodes(entree: episodes, famille: .accessoryRectangular), largeur: 172)
                    verrouille(VueAVenir(entree: aVenir, famille: .accessoryRectangular), largeur: 172)
                }
                HStack(spacing: 12) {
                    verrouille(VueSoiree(entree: soiree, famille: .accessoryCircular), largeur: 76)
                    verrouille(VueSoiree(entree: soiree, famille: .accessoryRectangular), largeur: 172)
                }
                verrouille(VueAVenir(entree: aVenir, famille: .accessoryInline), largeur: 300, hauteur: 26)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.eleve)
        .navigationTitle("Aperçu des widgets")
        .task { await chargerAffiches() }
    }

    private func groupe(_ titre: String) -> some View {
        Text(titre).font(.headline).foregroundStyle(.white)
    }

    private func ecran<Contenu: View>(_ contenu: Contenu, largeur: CGFloat, hauteur: CGFloat) -> some View {
        contenu
            .padding(16)
            .frame(width: largeur, height: hauteur)
            .background(FondWidget())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func verrouille<Contenu: View>(_ contenu: Contenu, largeur: CGFloat, hauteur: CGFloat = 76) -> some View {
        contenu
            .frame(width: largeur, height: hauteur)
            .foregroundStyle(.white)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chargerAffiches() async {
        let chemins: [Int: String] = [108978: "/qrJOCIAcvPmyZ63KajWTalQtqPT.jpg", 324552: "/r687UV1zQ5KDB9AxRokRscWIRvt.jpg",
                                      129552: "/vxCFNBGQ9AeI6GLtnpML1gKuSSK.jpg", 245891: "/7yCzmVL0BI1aSvzgN3jCtXLtyFR.jpg"]
        var images: [Int: Data] = [:]
        for (id, chemin) in chemins {
            if let url = URL(string: "https://image.tmdb.org/t/p/w154\(chemin)"), let (donnees, _) = try? await URLSession.shared.data(from: url) {
                images[id] = donnees
            }
        }
        soiree = EntreeSoiree(date: .now, titres: soiree.titres.map { var t = $0; t.affiche = images[t.reference.tmdbID]; return t })
        episodes = EntreeEpisodes(date: .now, episodes: episodes.episodes.map { var e = $0; e.affiche = images[e.serieID]; return e })
        aVenir = EntreeAVenir(date: .now, echeances: aVenir.echeances.map { var e = $0; e.affiche = images[e.reference.tmdbID]; return e })
    }
}
#endif

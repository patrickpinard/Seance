import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Identifier » sur la TV (8.4), comme sur l'iPhone : ce que TMDB propose pour une vidéo du NAS ou un film du guide
/// que Séance n'a pas reconnu seule ; on choisit le bon, et toute l'œuvre le reprend, sur tous les appareils.
struct IdentificationTV: View {
    let demande: DemandeIdentification

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var fermer
    @State private var texte = ""
    @State private var type = TypeTitre.film
    @State private var propositions: [TitreResume] = []
    @State private var enCours = false
    @State private var erreur: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Identifier").font(.system(size: 58, weight: .heavy))
                    Text(demande.nom).font(.system(size: 28)).foregroundStyle(Theme.texte2).lineLimit(2)
                }
                HStack(alignment: .bottom, spacing: 24) {
                    ChampTV(titre: "Titre à chercher", invite: demande.recherche, texte: $texte)
                        .frame(maxWidth: 900)
                        .onSubmit { Task { await chercher() } }
                    ForEach([TypeTitre.film, .serie], id: \.self) { choix in
                        Button(choix == .film ? "Films" : "Séries") { type = choix }
                            .buttonStyle(BoutonTV(principal: type == choix))
                    }
                }
                .focusSection()

                if enCours {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 80)
                } else if let erreur {
                    VideTV(symbole: "wifi.exclamationmark", titre: "TMDB ne répond pas", message: erreur)
                } else if propositions.isEmpty {
                    VideTV(symbole: "magnifyingglass", titre: "Aucune proposition",
                           message: "Essaie un autre titre, en français ou dans sa langue d'origine.")
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 44, alignment: .top), count: 5), alignment: .leading, spacing: 50) {
                        ForEach(propositions) { titre in
                            Button { Task { await choisir(titre) } } label: { carte(titre) }
                                .buttonStyle(.card)
                        }
                    }
                    .focusSection()
                }
                Button("Annuler") { fermer() }.buttonStyle(BoutonTV())
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 60)
        }
        .background(Theme.fond.ignoresSafeArea())
        .onExitCommand { fermer() }
        .onAppear {
            texte = demande.recherche
            type = demande.type
        }
        .task(id: type) { await chercher() }
    }

    /// L'affiche, le titre et de quoi départager deux homonymes : l'année, le titre original, les votes.
    private func carte(_ titre: TitreResume) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ImageTV(url: ImageTMDB.url(titre.cheminAffiche, .affiche))
                .frame(width: 260, height: 390)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(titre.titre).font(.system(size: 24, weight: .semibold)).lineLimit(2)
                Text(faits(titre)).font(.system(size: 20)).foregroundStyle(Theme.texte2).lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 260, alignment: .leading)
    }

    private func faits(_ titre: TitreResume) -> String {
        var faits: [String] = [titre.date.map { String($0.annee) } ?? "Année inconnue"]
        if titre.titreOriginal != titre.titre { faits.append(titre.titreOriginal) }
        if titre.nombreVotes > 0 { faits.append("\(titre.nombreVotes) vote\(titre.nombreVotes > 1 ? "s" : "")") }
        return faits.joined(separator: " · ")
    }

    private func chercher() async {
        guard let tmdb = etat.tmdb else {
            erreur = "La clé TMDB manque : ajoute-la dans Réglages."
            return
        }
        enCours = true
        erreur = nil
        defer { enCours = false }
        do {
            propositions = try await IdentificationsTMDB.propositions(texte, type: type, annee: demande.annee, recherche: tmdb)
        } catch is CancellationError {
            return
        } catch {
            erreur = "Réessaie dans un instant."
        }
    }

    private func choisir(_ titre: TitreResume) async {
        await etat.identifier(demande, titre: titre, contexte: contexte)
        fermer()
    }
}

/// Les titres identifiés à la main (8.4), dans Réglages › NAS ou Réglages › TV : on change le choix, ou on l'oublie.
struct SectionIdentifiesTV: View {
    let guide: Bool
    @Binding var demande: DemandeIdentification?

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var choix: [(cle: String, identification: IdentificationTMDB)] = []
    @State private var question: (cle: String, identification: IdentificationTMDB)?

    var body: some View {
        Group {
            if !choix.isEmpty {
                SectionTV(titre: "Identifiés à la main",
                          explication: "Les titres que tu as choisis parmi les propositions de TMDB ; oublie-en un pour que Séance le cherche de nouveau seule.") {
                    ForEach(choix, id: \.cle) { entree in
                        LigneTVReglage(titre: libelle(entree.identification),
                                       detail: ((entree.identification.nom ?? "") as NSString).lastPathComponent,
                                       symbole: "checkmark.seal", action: { question = entree }) { BoutTV(forme: .chevron) }
                    }
                }
            }
        }
        .onAppear(perform: relire)
        .onChange(of: demande) { if demande == nil { relire() } }
        .fullScreenCover(isPresented: Binding { question != nil } set: { if !$0 { question = nil } }) {
            if let entree = question {
                DialogueTV(titre: libelle(entree.identification), message: ((entree.identification.nom ?? "") as NSString).lastPathComponent, choix: [
                    DialogueTV.Choix(libelle: "Choisir un autre titre", principal: true) {
                        demande = DemandeIdentification.depuis(cle: entree.cle, nom: entree.identification.nom)
                    },
                    DialogueTV.Choix(libelle: "Oublier ce choix") { Task { await oublier(entree) } },
                    DialogueTV.Choix(libelle: "Annuler") {},
                ])
            }
        }
    }

    private func libelle(_ identification: IdentificationTMDB) -> String {
        guard let titre = identification.titre else { return "" }
        return titre.date.map { "\(titre.titre) (\($0.annee))" } ?? titre.titre
    }

    private func relire() {
        choix = IdentificationsTMDB.lues().choisis(guide: guide)
    }

    private func oublier(_ entree: (cle: String, identification: IdentificationTMDB)) async {
        if let demande = DemandeIdentification.depuis(cle: entree.cle, nom: entree.identification.nom) {
            await etat.identifier(demande, titre: nil, contexte: contexte)
        }
        relire()
    }
}

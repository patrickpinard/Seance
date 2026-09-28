import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

extension EtatApp {
    /// Le film du guide choisi à la main (8.4), ou oublié : le guide se relit aussitôt pour le montrer — ou le retirer.
    func identifier(_ demande: DemandeIdentification, titre: TitreResume?, contexte: ModelContext) async throws {
        switch demande.cible {
        case .nas(let chemin):
            try nas.identifier(chemin: chemin, titre: titre, contexte: contexte)
        case .guide(let programme, let annee):
            var identifications = IdentificationsTMDB.lues()
            let cle = IdentificationsTMDB.cleGuide(titre: programme, type: demande.type, annee: annee)
            if let titre { identifications.choisir(titre, pour: cle, nom: programme) } else { identifications.oublier(cle) }
            identifications.enregistrer()
            await actualiserTele(contexte: contexte, force: true)
        }
    }
}

/// « Identifier » : ce que TMDB propose pour un titre que Séance n'a pas reconnu seule ; on touche le bon, et toute
/// l'œuvre le reprend — sur cet appareil tout de suite, sur les autres à la prochaine synchronisation.
struct FeuilleIdentification: View {
    let demande: DemandeIdentification

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var fermer
    @State private var texte = ""
    @State private var type = TypeTitre.film
    @State private var propositions: [TitreResume] = []
    @State private var enCours = false
    @State private var erreur: String?
    @State private var choisi: TitreResume?
    @State private var aide = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text(demande.nom).font(.subheadline.weight(.semibold)).lineLimit(3)
                        Spacer()
                        Button { aide = true } label: {
                            Image(systemName: "info.circle").zoneDeToucher()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Pourquoi identifier ce titre")
                        .popover(isPresented: $aide) {
                            BulleAide(titre: "Pas reconnu sans hésiter",
                                      texte: "Séance ne rattache un titre à TMDB que s'il n'y a aucun doute : même nom et même année. Deux films du même nom sortis la même année, ou un nom de fichier sans titre lisible, restent de côté. Touche le bon : Séance s'en souviendra, sur tous tes appareils.")
                        }
                    }
                    SelecteurPuces(selection: $type, choix: [.init(valeur: .film, nom: "Films"), .init(valeur: .serie, nom: "Séries")])
                        .padding(.horizontal, -20)
                }
                .listRowBackground(Color.clear)

                Section {
                    if enCours {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let erreur {
                        Label(erreur, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                    } else if propositions.isEmpty {
                        Text("TMDB ne propose rien pour « \(texte) ». Essaie un autre titre, en français ou dans sa langue d'origine.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(propositions) { titre in
                        Button { Task { await choisir(titre) } } label: { ligne(titre) }
                            .buttonStyle(.plain)
                            .disabled(choisi != nil)
                            .accessibilityIdentifier("proposition-\(titre.reference.tmdbID)")
                    }
                } header: {
                    Text("Propositions de TMDB")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .searchable(text: $texte, placement: .navigationBarDrawer(displayMode: .always), prompt: "Titre à chercher")
            .onSubmit(of: .search) { Task { await chercher() } }
            .titreDeFeuille("Identifier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { fermer() } }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.fond)
        .sensoryFeedback(.success, trigger: choisi)
        .onAppear {
            texte = demande.recherche
            type = demande.type
        }
        .task(id: type) { await chercher() }
    }

    private func ligne(_ titre: TitreResume) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ImageDistante(url: ImageTMDB.url(titre.cheminAffiche, .portrait), coins: 8)
                .frame(width: 56, height: 84)
            VStack(alignment: .leading, spacing: 3) {
                Text(titre.titre).font(.headline).lineLimit(2)
                Text(faits(titre)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !titre.synopsis.isEmpty {
                    Text(titre.synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if choisi?.reference == titre.reference {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.vert)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Retient ce titre")
    }

    /// « 2026 · The Runner · 1 240 votes » : de quoi départager deux homonymes.
    private func faits(_ titre: TitreResume) -> String {
        var faits: [String] = [titre.date.map { String($0.annee) } ?? "Année inconnue"]
        if titre.titreOriginal != titre.titre { faits.append(titre.titreOriginal) }
        if titre.nombreVotes > 0 { faits.append("\(titre.nombreVotes) vote\(titre.nombreVotes > 1 ? "s" : "")") }
        return faits.joined(separator: " · ")
    }

    private func chercher() async {
        guard let tmdb = etat.tmdb else {
            erreur = "Ajoute d'abord ta clé TMDB dans Réglages."
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
            erreur = "TMDB ne répond pas. Réessaie dans un instant."
        }
    }

    private func choisir(_ titre: TitreResume) async {
        choisi = titre
        do {
            try await etat.identifier(demande, titre: titre, contexte: contexte)
            try? await Task.sleep(for: .milliseconds(350))
            fermer()
        } catch {
            choisi = nil
            erreur = "Le choix n'a pas pu être enregistré."
        }
    }
}

/// Les titres identifiés à la main (8.4), à changer ou à oublier : dans Réglages › NAS et Réglages › TV.
struct IdentifiesALaMain: View {
    let guide: Bool
    @Binding var demande: DemandeIdentification?

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var choix: [(cle: String, identification: IdentificationTMDB)] = []
    @State private var visibles = false

    var body: some View {
        Group {
            if !choix.isEmpty {
                DisclosureGroup("Identifiés à la main (\(choix.count))", isExpanded: $visibles) {
                    ForEach(choix, id: \.cle) { entree in
                        HStack(spacing: 12) {
                            Button {
                                demande = DemandeIdentification.depuis(cle: entree.cle, nom: entree.identification.nom)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entree.identification.titre.map { titre in titre.date.map { "\(titre.titre) (\($0.annee))" } ?? titre.titre } ?? "")
                                        .font(.subheadline)
                                    Text(((entree.identification.nom ?? "") as NSString).lastPathComponent)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Choisir un autre titre")
                            Button("Oublier", role: .destructive) { Task { await oublier(entree.cle, nom: entree.identification.nom) } }
                                .buttonStyle(.borderless)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .onAppear(perform: relire)
        .onChange(of: demande) { if demande == nil { relire() } }
    }

    private func relire() {
        choix = IdentificationsTMDB.lues().choisis(guide: guide)
    }

    private func oublier(_ cle: String, nom: String?) async {
        if let demande = DemandeIdentification.depuis(cle: cle, nom: nom) {
            try? await etat.identifier(demande, titre: nil, contexte: contexte)
        } else {
            var identifications = IdentificationsTMDB.lues()
            identifications.oublier(cle)
            identifications.enregistrer()
        }
        relire()
    }
}

import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// Réglages › Toi : prénom et suggestions du soir.

/// Ton prénom : Séance s'en sert pour te saluer sur l'accueil et quand elle te propose des idées. Il reste sur l'appareil.
struct ReglagesPrenomView: View {
    @AppStorage(Prenom.cle) private var prenom = ""
    @AppStorage(NombreIdees.cle) private var nombreIdees = NombreIdees.parDefaut
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    /// « Je n'aime pas », « Jamais », « Ni VF ni sous-titres » : ce que Séance ne te propose plus.
    @Query(filter: #Predicate<Suivi> { $0.statutBrut == "exclu" || $0.exclusionLangue }, sort: \Suivi.titre) private var ecartes: [Suivi]
    @State private var confirmationToutReproposer = false
    /// 👍 Ce que tu as dit aimer, le plus récent d'abord.
    @Query(sort: \TitreAime.aimeLe, order: .reverse) private var aimes: [TitreAime]

    /// Ton image (8.2.3) : le symbole du profil en cours, montré en haut de chaque page à côté de ton prénom.
    @State private var symbole = ProfilsFamille().actif.symbole

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                    ForEach(ProfilsFamille.symboles, id: \.self) { choix in
                        Button {
                            symbole = choix
                            var profil = ProfilsFamille().actif
                            profil.symbole = choix
                            ProfilsFamille().modifier(profil)
                        } label: {
                            PastilleProfil(profil: ProfilFamille(id: "x", prenom: "", symbole: choix), taille: 44, actif: choix == symbole)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Image \(choix)")
                        .accessibilityAddTraits(choix == symbole ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Ton image")
            } footer: {
                Text("En haut de chaque page, à côté de ton prénom, et dans « Qui regarde ? ».")
            }
            Section {
                TextField("Ton prénom", text: $prenom)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                if Prenom.lire(prenom) != nil {
                    Button("Effacer", role: .destructive) { prenom = "" }
                }
            } header: {
                Text("Prénom")
            } footer: {
                Text(Prenom.lire(prenom).map { "« Des suggestions pour toi, \($0) » le soir. Ton prénom reste sur cet appareil." }
                     ?? "Séance te saluera par ton prénom sur l'accueil et quand elle te propose des suggestions. Sans prénom, les phrases restent neutres.")
            }

            Section {
                Picker("Suggestions à la fois", selection: Binding { NombreIdees.lire(nombreIdees) } set: { nombreIdees = $0 }) {
                    ForEach(NombreIdees.choix, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Suggestions pour ce soir")
            } footer: {
                Text("Le nombre de suggestions que « Suggestions pour ce soir » te montre à la fois. Celles que tu écartes sont remplacées par les suivantes.")
            }

            Section {
                if aimes.isEmpty {
                    Label("Aucun pouce levé pour l'instant", systemImage: "hand.thumbsup").foregroundStyle(.secondary)
                } else {
                    ForEach(aimes) { aime in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(aime.titre.isEmpty ? "Titre sans nom" : aime.titre)
                                Text(aime.reference.type == .film ? "Film" : "Série").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Retirer") { try? ServiceGouts(contexte: contexte).nePlusAimer(aime.reference) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Retirer le pouce de \(aime.titre)")
                        }
                    }
                }
            } header: {
                Text("Titres que tu aimes")
            } footer: {
                Text("Le pouce levé d'une fiche, d'une suggestion ou d'une affiche : pas besoin d'avoir vu le titre. Séance s'en sert pour tes goûts, donc pour les suggestions du soir ; il n'ajoute rien à tes listes. La note de 1 à 10, elle, se donne après avoir regardé.")
            }

            Section {
                if ecartes.isEmpty {
                    Label("Aucun titre écarté", systemImage: "hand.thumbsup").foregroundStyle(.secondary)
                } else {
                    ForEach(ecartes) { suivi in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suivi.titre.isEmpty ? "Titre sans nom" : suivi.titre)
                                Text(suivi.exclusionLangue ? "Ni VF ni sous-titres" : suivi.type == .film ? "Film" : "Série")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Reproposer") {
                                try? ServiceGouts(contexte: contexte).reproposer(suivi.reference)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Reproposer \(suivi.titre)")
                        }
                    }
                    Button("Tout reproposer (\(ecartes.count))", role: .destructive) { confirmationToutReproposer = true }
                        .accessibilityIdentifier("toutReproposer")
                }
            } header: {
                Text("Titres que tu as écartés")
            } footer: {
                Text("« Je n'aime pas » sur une suggestion, une affiche ou une fiche : le titre ne t'est plus proposé, ni dans les suggestions du soir, ni sur l'accueil, ni dans la recherche. « Tout reproposer » efface ces exclusions ; tes listes, tes notes et ce que tu as vu ne changent pas.")
            }
            .confirmationDialog("Reproposer les \(ecartes.count) titres écartés ?", isPresented: $confirmationToutReproposer, titleVisibility: .visible) {
                Button("Tout reproposer", role: .destructive) {
                    let nombre = (try? ServiceGouts(contexte: contexte).reproposerTout()) ?? 0
                    etat.confirmer(nombre > 1 ? "\(nombre) titres de nouveau proposés" : "Titre de nouveau proposé", symbole: "hand.thumbsup.fill")
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ils pourront revenir dans les suggestions du soir, sur l'accueil et dans la recherche.")
            }
        }
        .pageReglages("Toi")
    }
}


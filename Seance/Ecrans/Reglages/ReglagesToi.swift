import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// Réglages › Toi : prénom et idées du soir, apparence.

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

    var body: some View {
        Form {
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
                Text(Prenom.lire(prenom).map { "« \(Prenom.salut($0)) » sur l'accueil, « Des idées pour toi, \($0) » le soir. Ton prénom reste sur cet appareil." }
                     ?? "Séance te saluera par ton prénom sur l'accueil et quand elle te propose des idées. Sans prénom, les phrases restent neutres.")
            }

            Section {
                Picker("Idées à la fois", selection: Binding { NombreIdees.lire(nombreIdees) } set: { nombreIdees = $0 }) {
                    ForEach(NombreIdees.choix, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Idées pour ce soir")
            } footer: {
                Text("Le nombre d'idées que « Idées pour ce soir » te montre à la fois. Celles que tu écartes sont remplacées par les suivantes.")
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
                Text("👍 Titres que tu aimes")
            } footer: {
                Text("Le pouce levé d'une fiche, d'une idée ou d'une affiche : pas besoin d'avoir vu le titre. Séance s'en sert pour tes goûts, donc pour les idées du soir ; il n'ajoute rien à tes listes. La note de 1 à 10, elle, se donne après avoir regardé.")
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
                Text("« Je n'aime pas » sur une idée, une affiche ou une fiche : le titre ne t'est plus proposé, ni dans les idées du soir, ni sur l'accueil, ni dans Explorer. « Tout reproposer » efface ces exclusions ; tes listes, tes notes et ce que tu as vu ne changent pas.")
            }
            .confirmationDialog("Reproposer les \(ecartes.count) titres écartés ?", isPresented: $confirmationToutReproposer, titleVisibility: .visible) {
                Button("Tout reproposer", role: .destructive) {
                    let nombre = (try? ServiceGouts(contexte: contexte).reproposerTout()) ?? 0
                    etat.confirmer(nombre > 1 ? "\(nombre) titres de nouveau proposés" : "Titre de nouveau proposé", symbole: "hand.thumbsup.fill")
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ils pourront revenir dans les idées du soir, sur l'accueil et dans Explorer.")
            }
        }
        .pageReglages("Toi")
    }
}

/// Sombre, clair, ou comme l'appareil : trois aperçus à toucher.
struct ReglagesApparenceView: View {
    @AppStorage(Apparence.cle) private var apparence = Apparence.sombre.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Apparence.allCases) { choix in
                        let actif = Apparence.lire(apparence) == choix
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) { apparence = choix.rawValue }
                        } label: {
                            VStack(spacing: 10) {
                                apercu(choix)
                                    .frame(height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(actif ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.trait), lineWidth: actif ? 3 : 1)
                                    }
                                Label(choix.nom, systemImage: actif ? "checkmark.circle.fill" : choix.symbole)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundStyle(actif ? AnyShapeStyle(Theme.accentClair) : AnyShapeStyle(.primary))
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Apparence \(choix.nom)")
                        .accessibilityAddTraits(actif ? .isSelected : [])
                    }
                }
                Text("Sombre est l'apparence d'origine de Séance, pensée pour le soir. « Automatique » suit le réglage de ton appareil, et change avec lui. Les grandes images gardent leur texte clair dans les deux cas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.fond)
        .navigationTitle("Apparence")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Une page miniature : un bandeau, un titre, deux affiches. « Automatique » montre les deux moitiés.
    @ViewBuilder
    private func apercu(_ choix: Apparence) -> some View {
        switch choix {
        case .sombre: miniature(sombre: true)
        case .clair: miniature(sombre: false)
        case .systeme:
            GeometryReader { geometrie in
                ZStack(alignment: .leading) {
                    miniature(sombre: false)
                    miniature(sombre: true)
                        .mask(alignment: .leading) { Rectangle().frame(width: geometrie.size.width / 2) }
                }
            }
        }
    }

    private func miniature(sombre: Bool) -> some View {
        let fond = sombre ? Color(red: 0.04, green: 0.04, blue: 0.055) : Color(red: 0.965, green: 0.96, blue: 0.955)
        let encre = sombre ? Color.white : Color.black
        return VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 5).fill(Theme.degradeAccent).frame(height: 34)
            RoundedRectangle(cornerRadius: 2).fill(encre.opacity(0.75)).frame(width: 46, height: 6)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(encre.opacity(0.14)).frame(height: 38)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(fond)
    }
}

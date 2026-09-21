import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Réglages › Famille (6.0) : les personnes de la maison. Chacune a ses listes, ses notes, ses pouces et ses idées du
/// soir ; les plateformes, les chaînes, le NAS et les clés sont ceux du foyer. Le profil principal ne se supprime pas.
struct FamilleView: View {
    @State private var profils = ProfilsFamille().profils
    @State private var actif = ProfilsFamille().actif
    @State private var demander = ProfilsFamille().demanderAuLancement
    @State private var nouveau = false
    @State private var aModifier: ProfilFamille?
    @State private var aSupprimer: ProfilFamille?
    @AppStorage(Prenom.cle) private var prenom = ""

    private let famille = ProfilsFamille()

    var body: some View {
        Form {
            Section {
                ForEach(profils) { profil in
                    HStack(spacing: 14) {
                        PastilleProfil(profil: profil, taille: 40, actif: profil.id == actif.id)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nom(profil)).font(.headline)
                            Text(profil.id == actif.id ? "Profil en cours" : profil.estPrincipal ? "Profil principal" : "Ses listes et ses goûts à part")
                                .font(.caption).foregroundStyle(profil.id == actif.id ? AnyShapeStyle(Theme.accentClair) : AnyShapeStyle(.secondary))
                        }
                        Spacer()
                        if profil.id != actif.id {
                            Button("Choisir") { ConteneurApp.changerDeProfil(vers: profil) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Passer au profil de \(nom(profil))")
                        }
                    }
                    .contentShape(Rectangle())
                    .swipeActions(edge: .trailing) {
                        if !profil.estPrincipal, profil.id != actif.id {
                            Button("Supprimer", role: .destructive) { aSupprimer = profil }
                        }
                        Button("Modifier") { aModifier = profil }.tint(Theme.accent)
                    }
                    .contextMenu {
                        Button { aModifier = profil } label: { Label("Modifier", systemImage: "pencil") }
                        if !profil.estPrincipal, profil.id != actif.id {
                            Button(role: .destructive) { aSupprimer = profil } label: { Label("Supprimer", systemImage: "trash") }
                        }
                    }
                }
                Button { nouveau = true } label: { Label("Ajouter une personne", systemImage: "person.badge.plus") }
                    .accessibilityIdentifier("ajouterProfil")
            } header: {
                Text("Qui regarde, ici ?")
            } footer: {
                Text("Chaque personne a ses listes, ses notes, ses pouces, ses soirées et ses idées du soir. Les plateformes, les chaînes, le NAS et les clés sont ceux de la maison : ils suivent d'un profil à l'autre. Glisse une ligne vers la gauche pour la modifier ou la supprimer.")
            }

            if profils.count > 1 {
                Section {
                    Toggle("Demander « Qui regarde ? » à l'ouverture", isOn: $demander).tint(Theme.accent)
                } footer: {
                    Text("Dans « Ce soir », « Qui regarde ce soir ? » mêle les goûts de plusieurs personnes pour proposer ce qui plaît à tous. Sur un autre appareil, crée un profil du même prénom : ils se synchronisent entre eux, dans le sous-dossier « Famille » du dossier de synchronisation. L'Apple TV et l'e-mail de la semaine suivent le profil principal.")
                }
            }
        }
        .pageReglages("Famille")
        .onChange(of: demander) { _, valeur in famille.demanderAuLancement = valeur }
        .sheet(isPresented: $nouveau, onDismiss: relire) { FicheProfil(profil: nil) }
        .sheet(item: $aModifier, onDismiss: relire) { FicheProfil(profil: $0) }
        .confirmationDialog("Supprimer le profil de \(aSupprimer.map(nom) ?? "") ?", isPresented: Binding { aSupprimer != nil } set: { if !$0 { aSupprimer = nil } },
                            titleVisibility: .visible) {
            Button("Supprimer ses listes et ses notes", role: .destructive) {
                if let profil = aSupprimer { famille.supprimer(profil) }
                relire()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ses listes, ses notes et ses goûts sont effacés de cet appareil. Ce qu'il a déposé dans le dossier de synchronisation y reste.")
        }
    }

    private func nom(_ profil: ProfilFamille) -> String {
        if !profil.prenom.isEmpty { return profil.prenom }
        return profil.estPrincipal ? (Prenom.lire(prenom) ?? "Moi") : "Sans prénom"
    }

    private func relire() {
        profils = famille.profils
        actif = famille.actif
    }
}

/// Un rond au symbole du profil, orange quand c'est lui qui regarde.
struct PastilleProfil: View {
    let profil: ProfilFamille
    var taille: CGFloat = 40
    var actif = false

    var body: some View {
        Image(systemName: profil.symbole)
            .font(.system(size: taille * 0.42, weight: .semibold))
            .foregroundStyle(actif ? Color.black : Theme.accentClair)
            .frame(width: taille, height: taille)
            .background(actif ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.accent.opacity(0.18)), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Créer ou modifier un profil : un prénom, un symbole de l'app.
private struct FicheProfil: View {
    let profil: ProfilFamille?
    @Environment(\.dismiss) private var fermer
    @State private var prenom = ""
    @State private var symbole = ProfilsFamille.symboles[1]

    var body: some View {
        NavigationStack {
            Form {
                Section("Prénom") {
                    TextField("Prénom", text: $prenom)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("prenomProfil")
                }
                Section("Symbole") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                        ForEach(ProfilsFamille.symboles, id: \.self) { choix in
                            Button { symbole = choix } label: {
                                PastilleProfil(profil: ProfilFamille(id: "x", prenom: "", symbole: choix), taille: 48, actif: choix == symbole)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Symbole \(choix)")
                            .accessibilityAddTraits(choix == symbole ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .titreDeFeuille(profil == nil ? "Nouvelle personne" : "Modifier le profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { fermer() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        let propre = prenom.trimmingCharacters(in: .whitespacesAndNewlines)
                        if var existant = profil {
                            existant.prenom = propre
                            existant.symbole = symbole
                            ProfilsFamille().modifier(existant)
                            if existant.id == ProfilsFamille().actif.id { UserDefaults.standard.set(propre, forKey: Prenom.cle) }
                        } else {
                            ProfilsFamille().ajouter(prenom: propre, symbole: symbole)
                        }
                        fermer()
                    }
                    .disabled(prenom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if let profil {
                prenom = profil.prenom.isEmpty && profil.estPrincipal ? (Prenom.lire() ?? "") : profil.prenom
                symbole = profil.symbole
            }
        }
    }
}

/// « Qui regarde ? » : à l'ouverture de l'app quand la maison a plusieurs profils, comme sur Netflix.
struct QuiRegardeView: View {
    let choisir: (ProfilFamille) -> Void
    private let profils = ProfilsFamille().profils
    private let actif = ProfilsFamille().actif
    @AppStorage(Prenom.cle) private var prenom = ""

    var body: some View {
        VStack(spacing: 34) {
            Image("Logo").resizable().scaledToFit().frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous)).accessibilityHidden(true)
            Text("Qui regarde ?").font(.largeTitle.weight(.heavy))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 20)], spacing: 24) {
                ForEach(profils) { profil in
                    Button { choisir(profil) } label: {
                        VStack(spacing: 10) {
                            PastilleProfil(profil: profil, taille: 92, actif: profil.id == actif.id)
                            Text(profil.prenom.isEmpty ? (profil.estPrincipal ? (Prenom.lire(prenom) ?? "Moi") : "Sans prénom") : profil.prenom)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(profil.id == actif.id ? .isSelected : [])
                }
            }
            .frame(maxWidth: 560)
            Text("Chacun retrouve ses listes, ses notes et ses idées. Réglages › Famille pour ajouter quelqu'un.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.fond.ignoresSafeArea())
    }
}

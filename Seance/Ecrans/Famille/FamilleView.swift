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
                    // 8.2.3 : glisser de droite à gauche, sur toute personne sauf le profil principal.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !profil.estPrincipal {
                            Button("Supprimer", role: .destructive) { aSupprimer = profil }
                        }
                        Button("Modifier") { aModifier = profil }.tint(Theme.accent)
                    }
                    .contextMenu {
                        Button { aModifier = profil } label: { Label("Modifier", systemImage: "pencil") }
                        if !profil.estPrincipal {
                            Button(role: .destructive) { aSupprimer = profil } label: { Label("Supprimer", systemImage: "trash") }
                        }
                    }
                }
                Button { nouveau = true } label: { Label("Ajouter une personne", systemImage: "person.badge.plus") }
                    .accessibilityIdentifier("ajouterProfil")
            } header: {
                Text("Qui regarde, ici ?")
            } footer: {
                Text("Chaque personne a ses listes, ses notes, ses pouces, ses soirées et ses suggestions du soir. Les plateformes, les chaînes, le NAS et les clés sont ceux de la maison : ils suivent d'un profil à l'autre. Glisse une ligne vers la gauche pour la modifier ou la supprimer.")
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
            if aSupprimer?.id == actif.id {
                // La personne en cours : son magasin est ouvert. On passe d'abord au profil principal.
                Button("Passer au profil principal") {
                    if let principal = profils.first(where: \.estPrincipal) { ConteneurApp.changerDeProfil(vers: principal) }
                }
            } else {
                Button("Supprimer ses listes et ses notes", role: .destructive) {
                    if let profil = aSupprimer { famille.supprimer(profil) }
                    relire()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(aSupprimer?.id == actif.id
                 ? "C'est la personne en cours : passe d'abord au profil principal, puis glisse de nouveau sa ligne pour la supprimer."
                 : "Ses listes, ses notes et ses goûts sont effacés de cet appareil. Ce qu'il a déposé dans le dossier de synchronisation y reste.")
        }
    }

    private func nom(_ profil: ProfilFamille) -> String {
        ProfilFamille.nomAffiche(profil, actif: actif, prenomDeLAppareil: prenom)
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
            .foregroundStyle(actif ? Color.black : Self.teinte(profil))
            .frame(width: taille, height: taille)
            .background(actif ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Self.teinte(profil).opacity(0.20)), in: Circle())
            .accessibilityHidden(true)
    }

    /// Une teinte par personne (6.4) : deux profils qui ont choisi le même symbole — deux cœurs — ne se
    /// distinguaient que par leur prénom. La couleur vient du prénom, elle est donc la même sur tous les appareils.
    static func teinte(_ profil: ProfilFamille) -> Color {
        let graine = profil.prenom.isEmpty ? profil.id : profil.prenom
        let somme = graine.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }
        // Autour de l'orange de Séance, sans jamais aller au rouge d'alerte ni au vert d'état.
        let teintes: [Double] = [24, 40, 200, 280, 320, 12, 170]
        return Color(hue: teintes[somme % teintes.count] / 360, saturation: 0.72, brightness: 0.95)
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
                // Le prénom de l'appareil n'est celui du profil principal que si c'est lui qui regarde.
                prenom = profil.prenom.isEmpty && profil.estPrincipal && profil.id == ProfilsFamille().actif.id ? (Prenom.lire() ?? "") : profil.prenom
                symbole = profil.symbole
            }
        }
    }
}

extension ProfilFamille {
    /// Le nom d'un profil à l'écran. Le profil principal sans prénom enregistré prend celui de l'appareil (Réglages › Toi)
    /// — mais seulement quand c'est lui qui regarde : ce prénom devient celui de la personne en cours à chaque changement,
    /// et « Qui regarde ? » montrait alors deux « Anne ».
    static func nomAffiche(_ profil: ProfilFamille, actif: ProfilFamille, prenomDeLAppareil: String) -> String {
        if !profil.prenom.isEmpty { return profil.prenom }
        guard profil.estPrincipal else { return "Sans prénom" }
        return (profil.id == actif.id ? Prenom.lire(prenomDeLAppareil) : nil) ?? "Moi"
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
                            Text(ProfilFamille.nomAffiche(profil, actif: actif, prenomDeLAppareil: prenom))
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
            Text("Chacun retrouve ses listes, ses notes et ses suggestions. Réglages › Famille pour ajouter quelqu'un.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.fond.ignoresSafeArea())
    }
}

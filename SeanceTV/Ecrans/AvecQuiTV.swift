import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Qui regarde avec toi ? » sur la TV (8.2), le même dialogue que sur l'iPhone : un film ou un épisode vu à plusieurs
/// s'inscrit aussi chez les autres personnes de la famille — dans leurs vus, hors de leur « À voir » —, directement,
/// puis leur sous-dossier de synchronisation part vers leurs appareils.
struct DemandeAvecQuiTV: Identifiable {
    let id = UUID()
    let reference: ReferenceTitre
    let titre: String
    /// Le même geste que chez soi, sur le magasin de chacun.
    let inscrire: @MainActor (ModelContext) async throws -> Void
}

extension EtatTV {
    /// Pose la question, seulement dans une maison à plusieurs personnes.
    func demanderAvecQui(_ reference: ReferenceTitre, titre: String, inscrire: @escaping @MainActor (ModelContext) async throws -> Void) {
        guard ConteneurTV.famille.aPlusieursProfils else { return }
        avecQui = DemandeAvecQuiTV(reference: reference, titre: titre, inscrire: inscrire)
    }
}

/// Les autres personnes de la famille, à cocher. Deux usages : avant la lecture (« Lancer »), et après — au bout d'une
/// lecture, après « Terminé » — pour inscrire le titre chez elles.
struct ChoixAvecQuiTV: View {
    enum Moment {
        /// Avant la lecture : le choix est retenu, puis la lecture démarre.
        case avant(titre: String, lancer: (Set<String>) -> Void)
        /// Après : le titre s'inscrit chez les personnes cochées.
        case apres(DemandeAvecQuiTV)
    }

    let moment: Moment
    let fermer: () -> Void

    @Environment(EtatTV.self) private var etat
    @State private var choisis: Set<String> = []
    @State private var enCours = false

    private var autres: [ProfilFamille] {
        let famille = ConteneurTV.famille
        return famille.profils.filter { $0.id != famille.actif.id }
    }

    private var titre: String {
        switch moment {
        case .avant(let titre, _): titre
        case .apres(let demande): demande.titre
        }
    }

    var body: some View {
        ZStack {
            Theme.fond.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Qui regarde avec toi ?").font(.system(size: 44, weight: .heavy))
                Text(message).font(.system(size: 26)).foregroundStyle(Theme.texte2).multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    ForEach(autres) { profil in
                        let coche = choisis.contains(profil.id)
                        Button {
                            if coche { choisis.remove(profil.id) } else { choisis.insert(profil.id) }
                        } label: {
                            HStack(spacing: 18) {
                                Image(systemName: coche ? "checkmark.circle.fill" : "circle")
                                Text(QuiRegardeTV.nom(profil))
                                Spacer()
                                Image(systemName: profil.symbole)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BoutonTV())
                        .accessibilityLabel("\(QuiRegardeTV.nom(profil)) regarde aussi")
                        .accessibilityAddTraits(coche ? .isSelected : [])
                    }
                }
                .focusSection()
                VStack(spacing: 16) {
                    Button { valider() } label: { Text(libelleValider).frame(maxWidth: .infinity) }
                        .buttonStyle(BoutonTV(principal: true))
                        .disabled(enCours)
                    if case .apres = moment, !choisis.isEmpty {
                        Button { fermer() } label: { Text("Juste moi").frame(maxWidth: .infinity) }
                            .buttonStyle(BoutonTV())
                    }
                }
                .padding(.top, 10)
                .focusSection()
            }
            .foregroundStyle(.white)
            .frame(width: 760)
            .padding(44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Theme.trait, lineWidth: 1))
        }
        .onExitCommand { fermer() }
        .onAppear {
            // Ceux choisis avant la lecture sont cochés d'office à la fin.
            if case .apres = moment { choisis = etat.compagnons.intersection(Set(autres.map(\.id))) }
        }
    }

    private var message: String {
        switch moment {
        case .avant: "« \(titre) » : coche les personnes qui regardent avec toi, il s'inscrira aussi chez elles à la fin."
        case .apres: "« \(titre) » s'inscrit aussi dans leurs vus, et quitte leur liste « À voir »."
        }
    }

    private var noms: String {
        ListFormatter.localizedString(byJoining: autres.filter { choisis.contains($0.id) }.map(QuiRegardeTV.nom))
    }

    private var libelleValider: String {
        switch moment {
        case .avant: choisis.isEmpty ? "Lancer, juste moi" : "Lancer avec \(noms)"
        case .apres: choisis.isEmpty ? "Juste moi" : "Aussi chez \(noms)"
        }
    }

    private func valider() {
        switch moment {
        case .avant(_, let lancer):
            etat.compagnons = choisis
            fermer()
            lancer(choisis)
        case .apres(let demande):
            guard !choisis.isEmpty else { return fermer() }
            enCours = true
            let profils = autres.filter { choisis.contains($0.id) }
            Task {
                let inscrits = await etat.inscrire(demande, chez: profils)
                fermer()
                if !inscrits.isEmpty { etat.dire("Aussi chez \(ListFormatter.localizedString(byJoining: inscrits))") }
            }
        }
    }
}

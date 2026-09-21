import SeanceDonnees
import SwiftUI

/// « Qui regarde ? » sur l'Apple TV (6.0.1) : à l'ouverture quand la maison a plusieurs profils, et depuis les Réglages.
/// Les personnes se créent sur l'iPhone, l'iPad ou le Mac (Réglages › Famille) et arrivent ici par la synchronisation.
struct QuiRegardeTV: View {
    let choisir: (ProfilFamille) -> Void

    private let profils = ConteneurTV.famille.profils
    private let actif = ConteneurTV.famille.actif

    var body: some View {
        VStack(spacing: 60) {
            Text("Qui regarde ?").font(.system(size: 76, weight: .heavy))
            HStack(spacing: 50) {
                ForEach(profils) { profil in
                    Button { choisir(profil) } label: {
                        VStack(spacing: 22) {
                            Image(systemName: profil.symbole)
                                .font(.system(size: 80, weight: .semibold))
                                .frame(width: 220, height: 220)
                                .background(profil.id == actif.id ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Color.white.opacity(0.14)), in: Circle())
                                .foregroundStyle(profil.id == actif.id ? Color.black : Theme.accentClair)
                            Text(Self.nom(profil)).font(.system(size: 34, weight: .bold))
                        }
                        .padding(30)
                    }
                    .buttonStyle(.card)
                }
            }
            Text(profils.count > 1 ? "Chacun retrouve ses listes, ses notes et ses idées."
                                   : "Une seule personne pour l'instant. Ajoute la famille sur ton iPhone : Réglages › Famille. Elle arrivera ici à la prochaine synchronisation.")
                .font(.system(size: 27)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 1200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.fond.ignoresSafeArea())
    }

    static func nom(_ profil: ProfilFamille) -> String {
        profil.prenom.isEmpty ? (profil.estPrincipal ? "Moi" : "Sans prénom") : profil.prenom
    }
}

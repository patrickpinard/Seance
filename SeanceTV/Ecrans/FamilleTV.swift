import SeanceDonnees
import SwiftUI

/// « Qui regarde ? » sur l'Apple TV (6.0.1) : à l'ouverture quand la maison a plusieurs profils, et depuis les Réglages.
/// Les personnes se créent sur l'iPhone, l'iPad ou le Mac (Réglages › Famille) et arrivent ici par la synchronisation.
struct QuiRegardeTV: View {
    let choisir: (ProfilFamille) -> Void

    private let profils = ConteneurTV.famille.profils
    private let actif = ConteneurTV.famille.actif

    /// Maquette 8.0, n° 1 : un rond par personne, son initiale dedans, le prénom dessous ; le focus agrandit et cerne.
    var body: some View {
        VStack(spacing: 60) {
            Text("Qui regarde ce soir ?").font(.system(size: 66, weight: .heavy))
            HStack(spacing: 60) {
                ForEach(Array(profils.enumerated()), id: \.element.id) { rang, profil in
                    Button { choisir(profil) } label: {
                        VStack(spacing: 22) {
                            Text(String(Self.nom(profil).prefix(1)).uppercased())
                                .font(.system(size: 90, weight: .heavy))
                                .foregroundStyle(.black)
                                .frame(width: 220, height: 220)
                                .background(Self.teinte(rang), in: Circle())
                            Text(Self.nom(profil)).font(.system(size: 32, weight: .bold))
                        }
                    }
                    .buttonStyle(ProfilTV())
                    .accessibilityLabel(Self.nom(profil))
                }
            }
            if profils.count < 2 {
                Text("Une seule personne pour l'instant. Ajoute la famille sur ton iPhone : Réglages › Famille.")
                    .font(.system(size: 26)).foregroundStyle(Theme.texte2).multilineTextAlignment(.center).frame(maxWidth: 1200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.fond.ignoresSafeArea())
    }

    /// Une couleur par personne, la première à l'orange de Séance, comme sur la maquette.
    static func teinte(_ rang: Int) -> AnyShapeStyle {
        rang == 0 ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.profils[(rang - 1) % Theme.profils.count])
    }

    /// Le focus : le rond grandit et se cerne de blanc.
    private struct ProfilTV: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { Corps(configuration: configuration) }
        private struct Corps: View {
            let configuration: Configuration
            @Environment(\.isFocused) private var aLeFocus
            var body: some View {
                configuration.label
                    .overlay(alignment: .top) {
                        if aLeFocus { Circle().strokeBorder(.white, lineWidth: 6).frame(width: 240, height: 240).offset(y: -10) }
                    }
                    .scaleEffect(aLeFocus ? 1.12 : 1)
                    .animation(.easeOut(duration: 0.15), value: aLeFocus)
            }
        }
    }

    static func nom(_ profil: ProfilFamille) -> String {
        profil.prenom.isEmpty ? (profil.estPrincipal ? "Moi" : "Sans prénom") : profil.prenom
    }
}

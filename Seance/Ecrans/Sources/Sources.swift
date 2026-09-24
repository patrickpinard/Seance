import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Les trois endroits où l'on regarde (7.0, maquette 1 du menu) : tes plateformes, la TV, ton NAS. Chacun a son entrée
/// dans le menu de l'iPad, du Mac et de l'Apple TV ; sur l'iPhone, où la barre ne tient que quatre onglets et la loupe,
/// ils se partagent l'onglet « Regarder », avec un sélecteur en tête.
enum SourceRegarder: String, CaseIterable, Hashable {
    case streaming, tele, nas

    var nom: String {
        switch self {
        case .streaming: "Streaming"
        case .tele: "TV"
        case .nas: "NAS"
        }
    }

    var symbole: String {
        switch self {
        case .streaming: "play.rectangle.on.rectangle"
        case .tele: "tv"
        case .nas: "externaldrive"
        }
    }

    var onglet: OngletRacine {
        switch self {
        case .streaming: .streaming
        case .tele: .tele
        case .nas: .nas
        }
    }
}

/// La page d'une source, telle que le menu l'ouvre : sa propre pile de navigation, les fiches à sa racine.
struct PageSource: View {
    let source: SourceRegarder

    var body: some View {
        NavigationStack {
            ContenuSource(source: source)
                .boutonBarreLaterale()
                .destinationsTitres()
                .destinationsAccueil()
        }
    }
}

/// L'onglet « Regarder » de l'iPhone : Streaming, TV ou NAS, au choix.
struct RegarderView: View {
    @Binding var source: SourceRegarder

    var body: some View {
        NavigationStack {
            ContenuSource(source: source)
                .id(source)
                .safeAreaInset(edge: .top, spacing: 0) {
                    SelecteurCases(selection: $source, cases: SourceRegarder.allCases.map { .init(valeur: $0, nom: $0.nom, symbole: $0.symbole) })
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Theme.fond)
                }
                .boutonBarreLaterale()
                .destinationsTitres()
                .destinationsAccueil()
        }
    }
}

private struct ContenuSource: View {
    let source: SourceRegarder
    @Environment(EtatApp.self) private var etat
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]

    var body: some View {
        switch source {
        case .streaming:
            if etat.tmdb == nil {
                InviteCleTMDB()
            } else if abonnements.isEmpty {
                EtatVide(symbole: "play.rectangle.on.rectangle", titre: "Aucune plateforme cochée",
                         message: "Coche tes abonnements — Netflix, Disney+, Prime Video… — et cette page montre ce qu'ils proposent de nouveau.",
                         libelleAction: "Choisir mes plateformes", symboleAction: "checklist") { etat.ongletDemande = .reglages }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.fond)
                    .navigationTitle("Streaming")
            } else {
                DuMomentView(choixPlateformes: true)
            }
        case .tele:
            ProgrammeTeleView()
        case .nas:
            NASView()
        }
    }
}

/// Les pages que l'accueil ouvre en grand : aussi déclarées à la racine des pages Streaming, TV et NAS.
extension View {
    func destinationsAccueil() -> some View {
        navigationDestination(for: DestinationAccueil.self) { destination in
            switch destination {
            case .nas: NASView()
            case .tele: ProgrammeTeleView()
            case .duMoment(let plateformes): DuMomentView(plateformes: plateformes)
            case .documentaires: DocumentairesView()
            }
        }
    }
}

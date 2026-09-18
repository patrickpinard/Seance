import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

@Suite("Grille télé")
@MainActor
struct GrilleTeleTests {
    private let calendrier: Calendar = {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendrier
    }()

    /// Vendredi 18 septembre 2026 à l'heure dite, à Zurich.
    private func heure(_ heure: Int, _ minute: Int = 0, jour: Int = 18) -> Date {
        calendrier.date(from: DateComponents(year: 2026, month: 9, day: jour, hour: heure, minute: minute))!
    }

    private func diffusion(_ titre: String, chaine: String, debut: Date, minutes: Int, serie: (id: Int?, saison: Int?, episode: Int?)? = nil,
                           dans contexte: ModelContext) -> Diffusion {
        let programme = ProgrammeTV(chaine: chaine, debut: debut, fin: debut.addingTimeInterval(Double(minutes) * 60), titre: titre)
        let diffusion = Diffusion(programme: programme, rattachement: nil)
        if let serie {
            diffusion.typeBrut = TypeTitre.serie.rawValue
            diffusion.tmdbID = serie.id
            diffusion.saison = serie.saison
            diffusion.episode = serie.episode
        } else {
            diffusion.typeBrut = TypeTitre.film.rawValue
            diffusion.tmdbID = 949
        }
        contexte.insert(diffusion)
        return diffusion
    }

    @Test func lesEpisodesQuiSEnchainentFontUnSeulBloc() throws {
        // Le conteneur doit vivre autant que son contexte.
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let diffusions = [
            diffusion("Un si grand soleil", chaine: "France3.fr", debut: heure(20, 45), minutes: 22, serie: (7, 8, 2), dans: contexte),
            diffusion("Un si grand soleil", chaine: "France3.fr", debut: heure(20, 25), minutes: 20, serie: (7, 8, 1), dans: contexte),
            diffusion("Heat", chaine: "Arte.fr", debut: heure(20, 55), minutes: 170, dans: contexte),
            // Même série, autre chaîne : un bloc à part.
            diffusion("Un si grand soleil", chaine: "RTS1.ch", debut: heure(20, 50), minutes: 20, serie: (7, 8, 1), dans: contexte),
            // Même chaîne, mais après une longue pause : un nouveau bloc.
            diffusion("Un si grand soleil", chaine: "France3.fr", debut: heure(23, 30), minutes: 20, serie: (7, 8, 3), dans: contexte),
        ]
        let blocs = GrilleTele.blocs(diffusions)
        #expect(blocs.map(\.diffusions.count) == [2, 1, 1, 1])
        #expect(blocs[0].libelleEpisodes == "S08E01 et E02")
        #expect(blocs[0].debut == heure(20, 25))
        #expect(blocs[0].fin == heure(21, 7))
        #expect(blocs[0].dureeMinutes == 42)
        #expect(blocs[0].reference == ReferenceTitre(type: .serie, tmdbID: 7))
        #expect(blocs[2].estFilm)
        #expect(blocs[2].libelleEpisodes == nil)
    }

    @Test func libellesDesEpisodes() throws {
        // Le conteneur doit vivre autant que son contexte.
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let quatre = (1...4).map {
            diffusion("Antigang", chaine: "TF1.fr", debut: heure(21, 10).addingTimeInterval(Double($0 - 1) * 3000), minutes: 50, serie: (9, 2, $0), dans: contexte)
        }
        #expect(GrilleTele.blocs(quatre).first?.libelleEpisodes == "S02E01 à E04")
        // Sans identifiant TMDB, le titre du guide fait foi ; sans numéros, on compte les épisodes.
        let sansNumero = [
            diffusion("Scènes de ménages", chaine: "M6.fr", debut: heure(20, 40), minutes: 15, serie: (nil, nil, nil), dans: contexte),
            diffusion("Scènes de Ménages", chaine: "M6.fr", debut: heure(20, 55), minutes: 15, serie: (nil, nil, nil), dans: contexte),
        ]
        let bloc = try #require(GrilleTele.blocs(sansNumero).first)
        #expect(bloc.diffusions.count == 2)
        #expect(bloc.libelleEpisodes == "2 épisodes")
        #expect(bloc.reference == nil)
    }

    @Test func momentsDeLaJourneeEtAvancement() throws {
        // Le conteneur doit vivre autant que son contexte.
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let maintenant = heure(14, 30)
        func bloc(_ debut: Date, minutes: Int = 120) -> BlocDiffusion {
            GrilleTele.blocs([diffusion("Heat", chaine: "Arte.fr", debut: debut, minutes: minutes, dans: contexte)])[0]
        }
        let enCours = bloc(heure(13, 30))
        #expect(GrilleTele.moment(enCours, maintenant: maintenant, calendrier: calendrier) == .enCours)
        #expect(enCours.avancement(maintenant: maintenant) == 0.5)
        #expect(bloc(heure(16)).avancement(maintenant: maintenant) == nil)
        #expect(GrilleTele.moment(bloc(heure(16)), maintenant: maintenant, calendrier: calendrier) == .journee)
        #expect(GrilleTele.moment(bloc(heure(20, 55)), maintenant: maintenant, calendrier: calendrier) == .soiree)
        #expect(GrilleTele.moment(bloc(heure(23, 5)), maintenant: maintenant, calendrier: calendrier) == .nuit)
        #expect(GrilleTele.moment(bloc(heure(1, 30, jour: 19)), maintenant: maintenant, calendrier: calendrier) == .nuit)
        // Un film de 1 h 30 du matin appartient à la soirée de la veille.
        #expect(calendrier.component(.day, from: GrilleTele.soir(bloc(heure(1, 30, jour: 19)), calendrier: calendrier)) == 18)
        #expect(calendrier.component(.day, from: GrilleTele.soir(bloc(heure(20, 55)), calendrier: calendrier)) == 18)
    }
}

import Foundation
import Testing
@testable import SeanceKit

@Suite("Lecture de l'envie du soir")
struct LectureEnvieTests {
    @Test func filmDeGuerre() {
        let envie = LectureEnvie.lire("film de guerre")
        #expect(envie.genresFilms == [10752])
        #expect(envie.genresSeries == [10768])
        #expect(envie.type == .film)
    }

    @Test func seriePoliciereCourte() {
        let envie = LectureEnvie.lire("Une série policière, plutôt courte")
        #expect(envie.genresSeries == [80])
        #expect(envie.type == .serie)
        #expect(envie.dureeMaxMinutes == 100)
    }

    @Test func actionSansHorreurEnMoinsDeDeuxHeures() {
        let envie = LectureEnvie.lire("De l'action mais sans horreur, 1h45 max")
        #expect(envie.genresFilms == [28])
        #expect(envie.genresExclusFilms == [27])
        #expect(envie.type == nil)
        #expect(envie.dureeMaxMinutes == 105)
    }

    @Test func expressionsEtRienDeReconnu() {
        #expect(LectureEnvie.lire("un bon SF des années 90").genresFilms == [878])
        #expect(LectureEnvie.lire("pas de comédie romantique ce soir").genresExclusFilms == [35, 10749])
        #expect(!LectureEnvie.lire("un truc nerveux").aDesGenres)
    }

    @Test func leClassementLocalRespecteLaDemande() {
        let guerre = Goûts.candidat(1, "Il faut sauver le soldat Ryan", genres: [10752, 18])
        let comedie = Goûts.candidat(2, "Intouchables", genres: [35])
        let demande = DemandeCeSoir(envie: "film de guerre")
        let classes = ClassementLocal.classer([comedie, guerre], profil: ProfilGouts(), demande: demande, nomsGenres: [10752: "Guerre"])
        #expect(classes.map(\.reference.tmdbID) == [1])
        #expect(classes.first?.phrase.hasPrefix("Guerre, comme tu l'as demandé") == true)
    }

    @Test func laCollecteInterrogeLeGenreDemande() async throws {
        let corps = try Fixture.donnees("discover_movie")
        let transport = TransportSimule(Array(repeating: .init(code: 200, corps: corps), count: 6))
        let collecteur = CollecteurCandidats(client: TMDBClient(identifiants: .jetonLecture("t"), transport: transport))
        _ = try await collecteur.candidats(pour: DemandeCeSoir(envie: "film de guerre"), profil: ProfilGouts(), contexte: .init())

        let genres = await transport.requetes.compactMap {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "with_genres" }?.value
        }
        #expect(!genres.isEmpty)
        #expect(genres.allSatisfy { $0 == "10752" })
        #expect(await transport.requetes.allSatisfy { $0.url?.path() == "/3/discover/movie" })
    }
}

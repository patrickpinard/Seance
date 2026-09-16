import Foundation
import Testing
@testable import SeanceKit

@Suite("Client Claude")
struct ClientClaudeTests {
    private func reponse(_ json: String, code: Int = 200) -> TransportSimule.Reponse {
        .init(code: code, corps: Data(json.utf8))
    }

    private func reponseClaude(_ suggestions: String, raisonArret: String = "end_turn") -> TransportSimule.Reponse {
        let texte = #"{\"suggestions\":[\#(suggestions)]}"#
        return reponse(#"{"content":[{"type":"text","text":"\#(texte)"}],"stop_reason":"\#(raisonArret)"}"#)
    }

    private let candidats = [
        Goûts.candidat(603, "Matrix", genres: [28, 878], duree: 136, acteurs: [6384: "Keanu Reeves"]),
        Goûts.candidat(245891, "John Wick", genres: [28, 53], duree: 101, acteurs: [6384: "Keanu Reeves"]),
    ]

    private func client(_ transport: TransportSimule, journal: JournalAttentes = JournalAttentes()) -> ClientClaude {
        ClientClaude(cle: "sk-ant-test", transport: transport, tentativesMax: 2) { await journal.noter($0) }
    }

    /// La clé part en en-tête, jamais dans l'adresse, et le schéma enferme la réponse
    /// dans la liste des candidats envoyés.
    @Test func laRequetePorteLaCleEtLEnumerationDesCandidats() async throws {
        let transport = TransportSimule([reponseClaude(#"{\"id\":\"film:603\",\"phrase\":\"Pour la nuque.\"}"#)])
        _ = try await client(transport).choisir(DemandeCeSoir(envie: "du nerf"), parmi: candidats,
                                                profil: ProfilGouts(), nomsGenres: Goûts.noms)

        let requete = try #require(await transport.requetes.first)
        #expect(requete.httpMethod == "POST")
        #expect(requete.url?.path() == "/v1/messages")
        #expect(requete.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(requete.value(forHTTPHeaderField: "anthropic-version") == ClientClaude.versionAPI)

        let corps = try JSONSerialization.jsonObject(with: try #require(requete.httpBody)) as! [String: Any]
        #expect(corps["model"] as? String == "claude-opus-5")
        let format = ((corps["output_config"] as! [String: Any])["format"] as! [String: Any])
        let schema = format["schema"] as! [String: Any]
        let items = ((schema["properties"] as! [String: Any])["suggestions"] as! [String: Any])["items"] as! [String: Any]
        let identifiant = (items["properties"] as! [String: Any])["id"] as! [String: Any]
        #expect(identifiant["enum"] as? [String] == ["film:603", "film:245891"])

        let messages = corps["messages"] as! [[String: String]]
        #expect(messages[0]["content"]?.contains("du nerf") == true)
        #expect(messages[0]["content"]?.contains("film:603 — Matrix (2020)") == true)
    }

    @Test func lesSuggestionsSontRelues() async throws {
        let transport = TransportSimule([reponseClaude(
            #"{\"id\":\"film:245891\",\"phrase\":\"Court et nerveux.\"},{\"id\":\"film:603\",\"phrase\":\"Le classique.\"}"#
        )])
        let choix = try await client(transport).choisir(DemandeCeSoir(), parmi: candidats, profil: ProfilGouts())

        #expect(choix.map(\.reference.tmdbID) == [245891, 603])
        #expect(choix.first?.phrase == "Court et nerveux.")
    }

    /// Le cahier l'exige : `stop_reason` se lit avant le contenu.
    @Test func leRefusEstUneErreurPasUneListeVide() async throws {
        let transport = TransportSimule([reponseClaude("", raisonArret: "refusal")])
        await #expect(throws: ErreurClaude.refus) {
            try await client(transport).choisir(DemandeCeSoir(), parmi: candidats, profil: ProfilGouts())
        }
    }

    @Test func cleRefusee() async throws {
        let transport = TransportSimule([reponse(#"{"error":{"message":"invalid x-api-key"}}"#, code: 401)])
        await #expect(throws: ErreurClaude.identifiantsRefuses) {
            try await client(transport).choisir(DemandeCeSoir(), parmi: candidats, profil: ProfilGouts())
        }
    }

    @Test func attendPuisReessayeApresUn429() async throws {
        let journal = JournalAttentes()
        let transport = TransportSimule([
            .init(code: 429, entetes: ["Retry-After": "3"]),
            reponseClaude(#"{\"id\":\"film:603\",\"phrase\":\"Le classique.\"}"#),
        ])
        let choix = try await client(transport, journal: journal)
            .choisir(DemandeCeSoir(), parmi: candidats, profil: ProfilGouts())

        #expect(choix.count == 1)
        #expect(await journal.durees == [.seconds(3)])
    }

    @Test func sansCandidatAucunAppel() async throws {
        let transport = TransportSimule([])
        #expect(try await client(transport).choisir(DemandeCeSoir(), parmi: [], profil: ProfilGouts()).isEmpty)
        #expect(await transport.requetes.isEmpty)
    }

    /// L'invite résume les goûts en toutes lettres : c'est ce que Claude lit.
    @Test func lInviteResumeLesGouts() {
        let profil = ProfilGouts.calculer(
            (1...10).map { _ in Goûts.note(9, genres: [28], acteurs: [6384: "Keanu Reeves"], duree: 110) },
            maintenant: Goûts.maintenant
        )
        let texte = InviteCeSoir.profilEnTexte(profil, Goûts.noms)

        #expect(texte.contains("Genres qu'il aime : Action"))
        #expect(texte.contains("Acteurs qu'il suit : Keanu Reeves"))
        #expect(texte.contains("110 min"))
    }
}

@Suite("Service de recommandation")
struct ServiceRecommandationTests {
    private let candidats = [
        Goûts.candidat(603, "Matrix", genres: [28]),
        Goûts.candidat(245891, "John Wick", genres: [28]),
    ]

    private func service(_ reponses: [TransportSimule.Reponse]) -> ServiceRecommandation {
        ServiceRecommandation(claude: ClientClaude(cle: "sk-ant-test", transport: TransportSimule(reponses), tentativesMax: 1))
    }

    private func reponseClaude(_ suggestions: String) -> TransportSimule.Reponse {
        let texte = #"{\"suggestions\":[\#(suggestions)]}"#
        return .init(code: 200, corps: Data(#"{"content":[{"type":"text","text":"\#(texte)"}],"stop_reason":"end_turn"}"#.utf8))
    }

    /// EF-25 : un identifiant absent de la liste est retiré, et rien ne vient le remplacer.
    @Test func unTitreHorsListeEstRetireJamaisRemplace() async {
        let resultat = await service([reponseClaude(
            #"{\"id\":\"film:999\",\"phrase\":\"Inventé.\"},{\"id\":\"film:603\",\"phrase\":\"Vérifié.\"}"#
        )]).suggerer(DemandeCeSoir(), candidats: candidats, profil: ProfilGouts())

        #expect(resultat.origine == .claude)
        #expect(resultat.suggestions.map(\.reference.tmdbID) == [603])
        #expect(resultat.suggestions.first?.phrase == "Vérifié.")
        #expect(resultat.avertissement?.contains("retirée") == true)
    }

    @Test func lOrdreDeClaudeEstConserve() async {
        let resultat = await service([reponseClaude(
            #"{\"id\":\"film:245891\",\"phrase\":\"D'abord.\"},{\"id\":\"film:603\",\"phrase\":\"Ensuite.\"}"#
        )]).suggerer(DemandeCeSoir(), candidats: candidats, profil: ProfilGouts())

        #expect(resultat.suggestions.map(\.reference.tmdbID) == [245891, 603])
        #expect(resultat.avertissement == nil)
    }

    /// EF-27 : sans clé Claude, le classement local prend la main sans rien dire de fâcheux.
    @Test func sansCleLeClassementEstLocal() async {
        let resultat = await ServiceRecommandation(claude: nil)
            .suggerer(DemandeCeSoir(), candidats: candidats, profil: ProfilGouts())

        #expect(resultat.origine == .local)
        #expect(resultat.suggestions.count == 2)
        #expect(resultat.avertissement == nil)
    }

    /// EF-27 : Claude injoignable, la soirée continue.
    @Test func claudeInjoignableReplieEnLocal() async {
        let resultat = await service([]).suggerer(DemandeCeSoir(), candidats: candidats, profil: ProfilGouts())

        #expect(resultat.origine == .local)
        #expect(resultat.suggestions.count == 2)
        #expect(resultat.avertissement?.contains("local") == true)
    }

    @Test func claudeRefuseEtLeDit() async {
        let refus = TransportSimule.Reponse(code: 200, corps: Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8))
        let resultat = await service([refus]).suggerer(DemandeCeSoir(), candidats: candidats, profil: ProfilGouts())

        #expect(resultat.origine == .local)
        #expect(resultat.avertissement == "Claude a préféré ne pas répondre : voici le classement local.")
    }

    /// Claude peut ne rien retenir : l'écran garde alors le repli local sous la main.
    @Test func claudeNeRetientRien() async {
        let resultat = await service([reponseClaude("")]).suggerer(DemandeCeSoir(), candidats: candidats, profil: ProfilGouts())

        #expect(resultat.suggestions.isEmpty)
        #expect(resultat.repliLocal.count == 2)
        #expect(resultat.avertissement == "Claude n'a rien retenu parmi les candidats du soir.")
    }

    @Test func leRepliLocalNEstPasRappeleQuandTouTVaBien() async {
        let resultat = await ServiceRecommandation(claude: nil, nombre: 1)
            .suggerer(DemandeCeSoir(), candidats: candidats, profil: ProfilGouts())
        #expect(resultat.suggestions.count == 1)
    }
}
